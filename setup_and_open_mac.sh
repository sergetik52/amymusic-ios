#!/bin/bash
set -e

echo "==================================================="
echo "  AmyMusic iOS 26 (Swift 6 + Liquid Glass) Setup   "
echo "==================================================="

cd "$(dirname "$0")"

if ! command -v xcodegen &> /dev/null; then
    echo "[1/3] Устанавливаем XcodeGen через Homebrew..."
    if command -v brew &> /dev/null; then
        brew install xcodegen
    else
        echo "Homebrew не найден. Открываем Package.swift напрямую в Xcode..."
        open Package.swift
        exit 0
    fi
fi

echo "[2/3] Генерируем проект AmyMusic.xcodeproj из project.yml..."
xcodegen generate

echo "[3/3] Открываем AmyMusic.xcodeproj в Xcode 26..."
open AmyMusic.xcodeproj

echo "Готово! В Xcode выберите ваш Development Team в Signing & Capabilities и нажмите Cmd + R."
