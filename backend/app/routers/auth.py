import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session

from app.auth import authenticate, create_access_token, get_current_user, hash_token, issue_refresh_token, password_hash
from app.db import get_db
from app.models import RefreshToken, User

router = APIRouter(prefix="/auth", tags=["auth"])


class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class RefreshIn(BaseModel):
    refresh_token: str


def _pair(db: Session, user: User) -> TokenPair:
    return TokenPair(access_token=create_access_token(user.id), refresh_token=issue_refresh_token(db, user.id))


@router.post("/register", response_model=TokenPair)
def register(body: Credentials, db: Session = Depends(get_db)) -> TokenPair:
    email = body.email.lower()
    if db.query(User).filter(User.email == email).one_or_none() is not None:
        raise HTTPException(status_code=409, detail="Email already registered")
    user = User(
        id=str(uuid.uuid4()),
        email=email,
        password_hash=password_hash.hash(body.password),
        created_at=datetime.now(UTC),
    )
    db.add(user)
    db.commit()
    pair = _pair(db, user)
    db.commit()
    return pair


@router.post("/login", response_model=TokenPair)
def login(body: Credentials, db: Session = Depends(get_db)) -> TokenPair:
    user = authenticate(db, body.email, body.password)
    if user is None:
        raise HTTPException(status_code=401, detail="Incorrect email or password")
    pair = _pair(db, user)
    db.commit()
    return pair


@router.post("/refresh", response_model=TokenPair)
def refresh(body: RefreshIn, db: Session = Depends(get_db)) -> TokenPair:
    row = db.query(RefreshToken).filter(RefreshToken.token_hash == hash_token(body.refresh_token)).one_or_none()
    if row is None or row.revoked:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    expires_at = row.expires_at if row.expires_at.tzinfo else row.expires_at.replace(tzinfo=UTC)
    if expires_at < datetime.now(UTC):
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    row.revoked = True
    user = db.get(User, row.user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    pair = _pair(db, user)
    db.commit()
    return pair


@router.post("/logout")
def logout(body: RefreshIn, db: Session = Depends(get_db), user: User = Depends(get_current_user)) -> dict:
    row = db.query(RefreshToken).filter(RefreshToken.token_hash == hash_token(body.refresh_token)).one_or_none()
    if row is None or row.user_id != user.id:
        raise HTTPException(status_code=404, detail="Token not found")
    row.revoked = True
    db.commit()
    return {"ok": True}
