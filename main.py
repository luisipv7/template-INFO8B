from fastapi import FastAPI

from database import create_db_and_tables
from routes import auth_router

app = FastAPI(title="Template INFO8B API")


@app.on_event("startup")
def on_startup():
    create_db_and_tables()


app.include_router(auth_router)
