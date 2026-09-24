import pytest
from pydantic import ValidationError

from app.config import DEV_JWT_SECRET, MIN_JWT_SECRET_BYTES, Settings


def test_rejects_a_jwt_secret_below_the_hs256_minimum():
    with pytest.raises(ValidationError, match="at least 32 bytes"):
        Settings(jwt_secret="too-short")


def test_rejects_the_development_default_outside_development():
    with pytest.raises(ValidationError, match="development default"):
        Settings(environment="production", jwt_secret=DEV_JWT_SECRET)


def test_accepts_a_real_secret_in_production():
    secret = "a" * MIN_JWT_SECRET_BYTES
    assert Settings(environment="production", jwt_secret=secret).jwt_secret == secret
