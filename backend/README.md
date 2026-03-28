# Smart Attendance Backend (FastAPI)

## Setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Run

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

API base URL: `http://localhost:8000`

## Endpoints

- `POST /decrypt` (multipart/form-data)
  - fields:
    - `sec_file`: encrypted `.sec` file
    - `private_key_file`: private key `.pem`
  - returns:
    - `{ "success": true, "decrypted_json": {...} }`

- `POST /process` (application/json)
  - body:
    - `decrypted_json`: object returned from `/decrypt`
    - `action`: `"update" | "download" | "both"`
    - `download_format`: `"csv" | "xlsx"` (only for download/both)
  - behavior:
    - `update`: returns clean records with only `student_id`, `student_name`
    - `download`: returns CSV/XLSX file bytes as HTTP attachment
    - `both`: returns update list + base64 file payload

## Quick curl examples

```bash
curl -X POST http://localhost:8000/decrypt \
  -F "sec_file=@/path/to/file.sec" \
  -F "private_key_file=@/path/to/instructor_private_key.pem"
```

```bash
curl -X POST http://localhost:8000/process \
  -H "Content-Type: application/json" \
  -d '{"decrypted_json":{"students":[{"student_id":"2019001","student_name":"Alice"}]},"action":"update"}'
```
