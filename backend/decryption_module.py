"""
ECIES decryption module used by FastAPI backend.

Format compatibility:
- version 2.0 secured package
- ECDH (SECP256R1) + HKDF-SHA256 + AES-256-GCM
"""

from __future__ import annotations

import base64
import json
from typing import Any, Dict

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

HKDF_INFO = b"smart-attendance-v1"


class ECCDecryption:
    """Decrypts a Smart Attendance `.sec` package."""

    def __init__(self) -> None:
        self._private_key = None

    def load_private_key_bytes(self, key_bytes: bytes) -> None:
        self._private_key = serialization.load_pem_private_key(
            key_bytes, password=None, backend=default_backend()
        )

    def decrypt_data(self, secured_package: Dict[str, Any]) -> Dict[str, Any]:
        if self._private_key is None:
            raise ValueError("Private key not loaded.")

        version = secured_package.get("version", "unknown")
        if version != "2.0":
            raise ValueError(
                f"Unsupported .sec format version '{version}'. "
                "Expected version '2.0'."
            )

        try:
            ephemeral_pub_pem = base64.b64decode(secured_package["ephemeral_pub_key"])
            wrap_nonce = base64.b64decode(secured_package["wrap_nonce"])
            wrapped_aes_key = base64.b64decode(secured_package["wrapped_aes_key"])
            nonce = base64.b64decode(secured_package["nonce"])
            ciphertext = base64.b64decode(secured_package["ciphertext"])
        except KeyError as exc:
            raise ValueError(f"Missing encrypted field: {exc}") from exc
        except Exception as exc:
            raise ValueError("Invalid base64 in encrypted payload.") from exc

        ephemeral_pub = serialization.load_pem_public_key(
            ephemeral_pub_pem, backend=default_backend()
        )

        shared_secret = self._private_key.exchange(ec.ECDH(), ephemeral_pub)
        wrap_key = HKDF(
            algorithm=hashes.SHA256(),
            length=32,
            salt=None,
            info=HKDF_INFO,
            backend=default_backend(),
        ).derive(shared_secret)

        wrap_aesgcm = AESGCM(wrap_key)
        aes_key = wrap_aesgcm.decrypt(wrap_nonce, wrapped_aes_key, None)

        aesgcm = AESGCM(aes_key)
        plaintext = aesgcm.decrypt(nonce, ciphertext, None)

        try:
            return json.loads(plaintext.decode("utf-8"))
        except Exception as exc:
            raise ValueError("Decrypted plaintext is not valid UTF-8 JSON.") from exc
