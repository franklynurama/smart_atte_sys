from __future__ import annotations

import base64
import csv
import io
import json
from typing import Any, Dict, List, Literal, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from openpyxl import Workbook
from pydantic import BaseModel, Field

from decryption_module import ECCDecryption


ProcessAction = Literal["update", "download", "both"]
DownloadFormat = Literal["csv", "xlsx"]


class ProcessRequest(BaseModel):
    decrypted_json: Dict[str, Any] = Field(default_factory=dict)
    action: ProcessAction
    download_format: Optional[DownloadFormat] = "csv"


app = FastAPI(title="Smart Attendance Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _extract_students_all_columns(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    students = payload.get("students")
    if not isinstance(students, list):
        raise ValueError("decrypted_json.students must be a list")

    base_meta = {
        "course_code": payload.get("course_code", ""),
        "date": payload.get("date", ""),
        "time": payload.get("time", ""),
        "device_id": payload.get("device_id", ""),
        "location": payload.get("location", ""),
    }

    rows: List[Dict[str, Any]] = []
    for item in students:
        if not isinstance(item, dict):
            continue
        row = dict(item)
        for k, v in base_meta.items():
            row.setdefault(k, v)
        rows.append(row)
    return rows


def _extract_update_rows(payload: Dict[str, Any]) -> List[Dict[str, str]]:
    students = payload.get("students")
    if not isinstance(students, list):
        raise ValueError("decrypted_json.students must be a list")

    clean: List[Dict[str, str]] = []
    for item in students:
        if not isinstance(item, dict):
            continue
        sid = str(item.get("student_id", "")).strip()
        sname = str(item.get("student_name", "")).strip()
        if not sid:
            continue
        clean.append({"student_id": sid, "student_name": sname})
    return clean


def _build_csv_bytes(rows: List[Dict[str, Any]]) -> bytes:
    if not rows:
        output = io.StringIO()
        writer = csv.writer(output)
        writer.writerow(["student_id", "student_name"])
        return output.getvalue().encode("utf-8")

    keys: List[str] = []
    seen = set()
    for row in rows:
        for k in row.keys():
            if k not in seen:
                keys.append(k)
                seen.add(k)

    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=keys)
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue().encode("utf-8")


def _build_xlsx_bytes(rows: List[Dict[str, Any]]) -> bytes:
    wb = Workbook()
    ws = wb.active
    ws.title = "Attendance"

    if not rows:
        ws.append(["student_id", "student_name"])
    else:
        keys: List[str] = []
        seen = set()
        for row in rows:
            for k in row.keys():
                if k not in seen:
                    keys.append(k)
                    seen.add(k)
        ws.append(keys)
        for row in rows:
            ws.append([row.get(k, "") for k in keys])

    buff = io.BytesIO()
    wb.save(buff)
    return buff.getvalue()


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.post("/decrypt")
async def decrypt(
    sec_file: UploadFile = File(...),
    private_key_file: UploadFile = File(...),
) -> Dict[str, Any]:
    try:
        sec_bytes = await sec_file.read()
        key_bytes = await private_key_file.read()
        if not sec_bytes:
            raise HTTPException(status_code=400, detail="Encrypted file is empty.")
        if not key_bytes:
            raise HTTPException(status_code=400, detail="Private key file is empty.")

        try:
            secured_package = json.loads(sec_bytes.decode("utf-8"))
        except Exception as exc:
            raise HTTPException(
                status_code=400,
                detail="Encrypted file is not valid JSON .sec format.",
            ) from exc

        decryptor = ECCDecryption()
        decryptor.load_private_key_bytes(key_bytes)
        decrypted = decryptor.decrypt_data(secured_package)
        return {"success": True, "decrypted_json": decrypted}
    except HTTPException:
        raise
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Decryption failed: {exc}",
        ) from exc


@app.post("/process")
async def process_attendance(request: ProcessRequest) -> Response:
    try:
        action = request.action
        fmt = request.download_format or "csv"

        if action in ("download", "both") and fmt not in ("csv", "xlsx"):
            raise HTTPException(status_code=400, detail="download_format must be csv or xlsx")

        update_rows: Optional[List[Dict[str, str]]] = None
        if action in ("update", "both"):
            update_rows = _extract_update_rows(request.decrypted_json)

        file_bytes: Optional[bytes] = None
        media_type: Optional[str] = None
        file_name: Optional[str] = None
        if action in ("download", "both"):
            rows = _extract_students_all_columns(request.decrypted_json)
            if fmt == "xlsx":
                file_bytes = _build_xlsx_bytes(rows)
                media_type = (
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                )
                file_name = "decrypted_attendance.xlsx"
            else:
                file_bytes = _build_csv_bytes(rows)
                media_type = "text/csv; charset=utf-8"
                file_name = "decrypted_attendance.csv"

        if action == "download":
            assert file_bytes is not None and media_type is not None and file_name is not None
            headers = {"Content-Disposition": f'attachment; filename="{file_name}"'}
            return Response(content=file_bytes, media_type=media_type, headers=headers)

        body: Dict[str, Any] = {"success": True}
        if update_rows is not None:
            body["update_records"] = update_rows
            body["update_count"] = len(update_rows)

        if action == "both":
            assert file_bytes is not None and media_type is not None and file_name is not None
            body["download"] = {
                "file_name": file_name,
                "mime_type": media_type,
                "content_base64": base64.b64encode(file_bytes).decode("ascii"),
            }

        return JSONResponse(content=body)
    except HTTPException:
        raise
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Process failed: {exc}") from exc

