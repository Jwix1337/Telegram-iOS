#!/usr/bin/env python3
"""Typecheck SnowEffect with Apple's iOS SDK, without compiling Telegram or signing."""
from pathlib import Path
import subprocess


def main():
    root = Path(__file__).resolve().parents[2]
    sources = sorted((root / 'submodules/SnowEffect/Sources').glob('*.swift'))
    if not sources:
        raise RuntimeError('SnowEffect sources are missing')
    sdk = subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip()
    print(f'Typechecking {len(sources)} SnowEffect source files against the iOS SDK', flush=True)
    subprocess.run([
        'xcrun', '--sdk', 'iphoneos', 'swiftc', '-typecheck', '-warnings-as-errors',
        '-module-name', 'SnowEffect', '-sdk', sdk, '-target', 'arm64-apple-ios15.0',
        *map(str, sources),
    ], check=True)


if __name__ == '__main__':
    main()
