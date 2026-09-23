import base64
import hashlib
import secrets  # Usado para gerar um Salt seguro aleatório

def hash_password(plain_password: str) -> str:
    # 1. Configurações padrão (iguais ao seu hash de exemplo)
    algorithm = "pbkdf2_sha256"
    iterations = 600000

    # 2. Gera um salt aleatório de 16 bytes e codifica em Base64 (sem quebras de linha)
    salt_bytes = secrets.token_bytes(16)
    salt_b64 = base64.b64encode(salt_bytes).decode("utf-8")

    # 3. Gera o hash usando pbkdf2_hmac
    password_hash = hashlib.pbkdf2_hmac(
        "sha256",
        plain_password.encode("utf-8"),
        salt_bytes,  # Passa os bytes do salt diretamente
        iterations,
    )

    # 4. Codifica o hash final em Base64
    hash_b64 = base64.b64encode(password_hash).decode("utf-8")

    # 5. Junta tudo no formato esperado: alg$iteracoes$salt$hash
    return f"{algorithm}${iterations}${salt_b64}${hash_b64}"