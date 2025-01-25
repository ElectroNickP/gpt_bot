#!/bin/bash
set -e

############################################
### 1. Проверка/обновление config.json
############################################

check_and_fix_config_json() {
  if [ ! -f "config.json" ]; then
    echo "❗ Файл config.json не найден. Создаём..."
    cat <<EOF > config.json
{
    "TELEGRAM_TOKEN": "<сюда нужно вставить токен из телеги>",
    "OPENAI_API_KEY": "<Сюда нужно вставить токен из гпт, который начинается на sk-proj-...",
    "ASSISTANT_ID": "<сюда нужно вставить айдишник ассистента из плейграунда>"
}
EOF
  fi

  get_json_field() {
    python3 -c "import json; data=json.load(open('config.json')); print(data.get('$1',''))" 2>/dev/null || echo ""
  }

  set_json_field() {
    python3 -c "
import json
data=json.load(open('config.json'))
data['$1']='$2'
with open('config.json','w') as f:
    json.dump(data,f,indent=4)
" 2>/dev/null || true
  }

  # 1) TELEGRAM_TOKEN
  CUR_TELE_TOKEN=$(get_json_field "TELEGRAM_TOKEN")
  if [[ "$CUR_TELE_TOKEN" == "<сюда нужно вставить токен из телеги>" || -z "$CUR_TELE_TOKEN" ]]; then
    echo "⚠ TELEGRAM_TOKEN не указан или содержит плейсхолдер."
    read -p "Введите TELEGRAM_TOKEN (Telegram Bot Token): " NEW_TELE_TOKEN
    set_json_field "TELEGRAM_TOKEN" "$NEW_TELE_TOKEN"
  fi

  # 2) OPENAI_API_KEY (должен начинаться с sk-proj-)
  CUR_OPENAI_KEY=$(get_json_field "OPENAI_API_KEY")
  if [[ "$CUR_OPENAI_KEY" == "<Сюда нужно вставить токен из гпт"* || -z "$CUR_OPENAI_KEY" || "$CUR_OPENAI_KEY" != sk-proj-* ]]; then
    echo "⚠ OPENAI_API_KEY не указан, содержит плейсхолдер или не начинается с sk-proj-..."
    read -p "Введите OPENAI_API_KEY (начинается с sk-proj-): " NEW_OPENAI_KEY
    set_json_field "OPENAI_API_KEY" "$NEW_OPENAI_KEY"
  fi

  # 3) ASSISTANT_ID
  CUR_ASSIST_ID=$(get_json_field "ASSISTANT_ID")
  if [[ "$CUR_ASSIST_ID" == "<сюда нужно вставить айдишник ассистента"* || -z "$CUR_ASSIST_ID" ]]; then
    echo "⚠ ASSISTANT_ID не указан или содержит плейсхолдер."
    read -p "Введите ASSISTANT_ID (например, asst_...): " NEW_ASSIST_ID
    set_json_field "ASSISTANT_ID" "$NEW_ASSIST_ID"
  fi
}

############################################
### 2. Создание/использование venv
############################################

install_python3() {
  echo "🔧 Устанавливаем python3, python3-pip, python3-venv..."
  sudo apt update && sudo apt install -y python3 python3-pip python3-venv || true
}

create_or_fix_venv() {
  local PYTHON_EXEC="$1"
  local VENV_DIR="$2"

  if [ ! -d "$VENV_DIR" ]; then
    echo "🔧 Создаём виртуальное окружение: $VENV_DIR..."
    "$PYTHON_EXEC" -m venv "$VENV_DIR" || true
  fi

  if [ ! -f "$VENV_DIR/bin/python3" ] && [ ! -f "$VENV_DIR/bin/python" ]; then
    echo "❌ Ошибка при создании $VENV_DIR, пробуем ещё раз после установки venv..."
    install_python3
    rm -rf "$VENV_DIR"
    "$PYTHON_EXEC" -m venv "$VENV_DIR" || true
  fi

  # Возвращаем 0, если хоть один питон есть:
  if [ -f "$VENV_DIR/bin/python3" ] || [ -f "$VENV_DIR/bin/python" ]; then
    return 0
  else
    return 1
  fi
}

############################################
### Старт скрипта
############################################
echo "🔄 Проверяем config.json..."
check_and_fix_config_json

# Проверяем Python
PYTHON_EXEC=$(command -v python3 || true)
if [ -z "$PYTHON_EXEC" ]; then
  install_python3
  PYTHON_EXEC=$(command -v python3 || true)
  if [ -z "$PYTHON_EXEC" ]; then
    echo "❌ Не удалось установить Python3!"
    exit 1
  fi
fi

echo "✅ Используем Python: $PYTHON_EXEC"

VENV_DIR="bot_env"
if create_or_fix_venv "$PYTHON_EXEC" "$VENV_DIR"; then
  echo "✅ Виртуальное окружение готово: $VENV_DIR"

  # Находим реально существующий питон внутри venv
  if [ -f "$VENV_DIR/bin/python3" ]; then
    PYTHON_VENV="$VENV_DIR/bin/python3"
  else
    PYTHON_VENV="$VENV_DIR/bin/python"
  fi

  # Убеждаемся, что pip есть (ensurepip)
  if ! "$PYTHON_VENV" -m pip --version &>/dev/null; then
    echo "🔧 Устанавливаем pip в окружении..."
    "$PYTHON_VENV" -m ensurepip --upgrade || true
  fi

  echo "📦 Устанавливаем зависимости..."
  if ! "$PYTHON_VENV" -m pip install --upgrade pip --break-system-packages &>/dev/null; then
    "$PYTHON_VENV" -m pip install --upgrade pip || true
  fi

  # Устанавливаем нужные пакеты
  "$PYTHON_VENV" -m pip install openai aiogram python-dotenv || true

  echo "🚀 Запускаем бота..."
  "$PYTHON_VENV" bot.py
else
  echo "❌ Не удалось создать venv! (Можно fallback на pipx/pip --user...)"
fi
