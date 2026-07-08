from typing import Annotated

from fastapi import APIRouter, Depends

from controller.auth import get_current_user, login, read_me
from models.auth import User
from schemas.auth import Token, UserRead

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=Token)
def auth_login(token: Annotated[Token, Depends(login)]) -> Token:
    return token


@router.get("/me", response_model=UserRead)
def auth_me(current_user: Annotated[User, Depends(get_current_user)]) -> User:
    return read_me(current_user)
