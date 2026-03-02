import modal

# Modal App definition
app = modal.App("strata")

# Image with all dependencies and auth data baked in
image = (
    modal.Image.debian_slim(python_version="3.11")
    .pip_install(
        "fastapi[standard]",
        "pyjwt",
        "bcrypt",
        "python-multipart",
    )
    .add_local_dir("auth", remote_path="/root/auth")
)


@app.function(image=image)
@modal.concurrent(max_inputs=10)
@modal.asgi_app()
def web():
    from fastapi import FastAPI
    from auth.auth import router as auth_router

    web_app = FastAPI(title="Strata API")

    @web_app.get("/health")
    def health():
        return {"status": "ok"}

    web_app.include_router(auth_router)

    return web_app
