from urllib.parse import urlparse

from pydantic import BaseModel, field_validator


class SendingGuideSettings(BaseModel):
    video_url: str = ""
    thumbnail_url: str = ""

    @field_validator("video_url", "thumbnail_url")
    @classmethod
    def validate_url(cls, value: str) -> str:
        value = value.strip()
        if value:
            parsed = urlparse(value)
            if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError("Utilisez un lien HTTPS public, sans identifiants.")
        return value


def sending_guide_payload(settings_doc: dict) -> dict:
    return {"sending_guide": settings_doc.get("sending_guide") or {"video_url": "", "thumbnail_url": ""}}
