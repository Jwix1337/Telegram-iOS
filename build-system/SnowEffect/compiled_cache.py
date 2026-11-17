#!/usr/bin/env python3
"""Bounded, authenticated encrypted Bazel disk cache for ephemeral CI runners.

Compiled BuildConfig may contain the app's API credentials. Only ciphertext and
its MAC enter GitHub Actions cache; plaintext stays in the disposable runner.
"""
import argparse
import hashlib
import hmac
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import tarfile
import tempfile

MAX_BYTES = 5 * 1024 ** 3


def keys():
    api_hash = os.environ.get('TELEGRAM_API_HASH', '')
    if not api_hash:
        return None
    material = (os.environ.get('TELEGRAM_API_ID', '') + '\0' + api_hash).encode()
    return tuple(hmac.digest(material, purpose, 'sha256') for purpose in
                 (b'TelegramSnow compiled-cache encryption v1', b'TelegramSnow compiled-cache authentication v1'))


def cipher(key, decrypt=False):
    env = dict(os.environ, SNOW_CACHE_CIPHER_KEY=key.hex())
    command = ['openssl', 'enc', '-aes-256-cbc', '-pbkdf2', '-iter', '200000',
               '-pass', 'env:SNOW_CACHE_CIPHER_KEY']
    if decrypt:
        command.append('-d')
    return command, env


def mac(path, key):
    digest = hmac.new(key, digestmod=hashlib.sha256)
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def save(source, bundle, secret, budget=MAX_BYTES):
    source, bundle = Path(source), Path(bundle)
    if not source.is_dir():
        return 0
    files = [p for p in source.rglob('*') if p.is_file() and not p.is_symlink()]
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    bundle.mkdir(parents=True, exist_ok=True)
    encrypted = bundle / 'actions.enc'
    command, env = cipher(secret[0])
    total = count = 0
    try:
        with encrypted.open('wb') as output, tempfile.TemporaryFile() as errors:
            process = subprocess.Popen(command, env=env, stdin=subprocess.PIPE, stdout=output, stderr=errors)
            try:
                with tarfile.open(fileobj=process.stdin, mode='w|gz', compresslevel=1) as archive:
                    for path in files:
                        size = path.stat().st_size
                        if total + size > budget:
                            continue
                        archive.add(path, arcname=path.relative_to(source).as_posix(), recursive=False)
                        total += size; count += 1
                process.stdin.close()
                if process.wait() != 0:
                    raise ValueError('Cache encryption failed')
            finally:
                if process.poll() is None:
                    process.kill(); process.wait()
        (bundle / 'actions.mac').write_text(mac(encrypted, secret[1]))
    except Exception:
        encrypted.unlink(missing_ok=True)
        (bundle / 'actions.mac').unlink(missing_ok=True)
        raise
    return count


def extract(archive, destination, budget=MAX_BYTES):
    total = 0
    for member in archive:
        name = PurePosixPath(member.name)
        if name.is_absolute() or '..' in name.parts or not name.parts or not member.isfile():
            raise ValueError('Invalid cache entry')
        total += member.size
        if total > budget:
            raise ValueError('Cache exceeds size limit')
        target = destination.joinpath(*name.parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.extractfile(member) as source, target.open('wb') as output:
            shutil.copyfileobj(source, output, length=1024 * 1024)


def restore(destination, bundle, secret):
    destination, bundle = Path(destination), Path(bundle)
    encrypted, signature = bundle / 'actions.enc', bundle / 'actions.mac'
    if not encrypted.is_file() or not signature.is_file():
        return False
    if encrypted.stat().st_size > MAX_BYTES + 128 * 1024 ** 2:
        raise ValueError('Encrypted cache exceeds size limit')
    # Authenticate BEFORE decryption, parsing or writing any archive member.
    if signature.stat().st_size > 128 or not hmac.compare_digest(mac(encrypted, secret[1]), signature.read_text().strip()):
        raise ValueError('Cache authentication failed')
    destination.parent.mkdir(parents=True, exist_ok=True)
    command, env = cipher(secret[0], decrypt=True)
    with tempfile.TemporaryDirectory(prefix='snow-cache-', dir=destination.parent) as staging, encrypted.open('rb') as stream, tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(command, env=env, stdin=stream, stdout=subprocess.PIPE, stderr=errors)
        try:
            with tarfile.open(fileobj=process.stdout, mode='r|gz') as archive:
                extract(archive, Path(staging))
            process.stdout.close()
            if process.wait() != 0:
                raise ValueError('Cache decryption failed')
            shutil.copytree(staging, destination, dirs_exist_ok=True)
        finally:
            if process.poll() is None:
                process.kill(); process.wait()
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['save', 'restore'])
    parser.add_argument('--cache', type=Path, required=True)
    parser.add_argument('--bundle', type=Path, required=True)
    args = parser.parse_args()
    secret = keys()
    if secret is None:
        print('Compiled cache skipped: own API credentials are unavailable')
        return
    try:
        if args.operation == 'save':
            print('Encrypted compiled cache saved:', save(args.cache, args.bundle, secret), 'entries; plaintext budget 5 GiB')
        else:
            print('Compiled cache restored' if restore(args.cache, args.bundle, secret) else 'No previous compiled cache; this build starts cold')
    except (ValueError, OSError, tarfile.TarError):
        # Cache is an optimization. Never print command environments or secret values.
        print('::warning::Compiled cache unavailable or invalid; continuing with a clean build')


if __name__ == '__main__':
    main()
