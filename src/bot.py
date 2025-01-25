import os
import sys
import subprocess
import logging
import json
import openai
import asyncio
from aiogram import Bot, Dispatcher
from aiogram.types import Message
from aiogram.filters import Command
from aiogram.client.default import DefaultBotProperties

# --- 📌 Глобальные переменные ---
VENV_DIR = "bot_env"

# --- 📌 Определение Python 3 ---
PYTHON_EXEC = sys.executable  # Определяем текущий Python

if "python" not in PYTHON_EXEC.lower():  # Если `python` не найден, пробуем `python3`
    PYTHON_EXEC = subprocess.run(["which", "python3"], capture_output=True, text=True).stdout.strip()
    if not PYTHON_EXEC:
        sys.exit("❌ Ошибка: Python 3 не найден! Установите его и попробуйте снова.")

# --- 📌 Проверяем, есть ли виртуальное окружение ---
if not os.path.exists(VENV_DIR):
    print(f"🔧 Виртуальное окружение не найдено. Создаю {VENV_DIR}...")
    
    # Создаём виртуальное окружение
    subprocess.run([PYTHON_EXEC, "-m", "venv", VENV_DIR], check=True)
    
    # Устанавливаем зависимости внутри venv
    venv_pip = os.path.join(VENV_DIR, "bin", "pip") if os.name != "nt" else os.path.join(VENV_DIR, "Scripts", "pip.exe")
    subprocess.run([venv_pip, "install", "-U", "openai", "aiogram", "python-dotenv"], check=True)
    
    print("✅ Виртуальное окружение создано и зависимости установлены!")

# --- 📌 Перезапуск скрипта внутри виртуального окружения ---
VENV_PYTHON = os.path.join(VENV_DIR, "bin", "python") if os.name != "nt" else os.path.join(VENV_DIR, "Scripts", "python.exe")

if sys.prefix != os.path.abspath(VENV_DIR):  # Проверяем, запущен ли код в venv
    print(f"🔄 Перезапускаю скрипт внутри виртуального окружения {VENV_DIR}...")
    os.execv(VENV_PYTHON, [VENV_PYTHON] + sys.argv)

# --- 📌 Функция загрузки конфигурации ---
def load_config():
    config_file = "config.json"
    
    if os.path.exists(config_file):
        with open(config_file, "r", encoding="utf-8") as f:
            return json.load(f)
    
    config = {
        "TELEGRAM_TOKEN": os.getenv("TELEGRAM_TOKEN", ""),
        "OPENAI_API_KEY": os.getenv("OPENAI_API_KEY", ""),
        "ASSISTANT_ID": os.getenv("ASSISTANT_ID", ""),
    }
    
    with open(config_file, "w", encoding="utf-8") as f:
        json.dump(config, f, indent=4)
    
    return config

# --- 📌 Загружаем конфигурацию ---
config = load_config()

TELEGRAM_TOKEN = config.get("TELEGRAM_TOKEN")
OPENAI_API_KEY = config.get("OPENAI_API_KEY")
ASSISTANT_ID = config.get("ASSISTANT_ID")

if not TELEGRAM_TOKEN or not OPENAI_API_KEY or not ASSISTANT_ID:
    sys.exit("❌ Ошибка: Проверь config.json и добавь необходимые ключи!")

# Логирование
logging.basicConfig(level=logging.INFO)

# Инициализация бота
bot = Bot(token=TELEGRAM_TOKEN, default=DefaultBotProperties(parse_mode="HTML"))
dp = Dispatcher()

# --- 📌 Функция запроса к OpenAI Assistants API v2 ---
async def ask_openai(prompt, thread_id=None):
    try:
        client = openai.OpenAI(api_key=OPENAI_API_KEY, default_headers={"OpenAI-Beta": "assistants=v2"})

        if not thread_id:
            thread = client.beta.threads.create()
            thread_id = thread.id

        client.beta.threads.messages.create(thread_id=thread_id, role="user", content=prompt)

        run = client.beta.threads.runs.create(thread_id=thread_id, assistant_id=ASSISTANT_ID)

        while True:
            run_status = client.beta.threads.runs.retrieve(thread_id=thread_id, run_id=run.id)
            if run_status.status == "completed":
                break
            await asyncio.sleep(2)

        messages = client.beta.threads.messages.list(thread_id=thread_id)
        last_message = messages.data[0].content[0].text.value

        return last_message, thread_id

    except openai.OpenAIError as e:
        logging.error(f"OpenAI API Error: {e}")
        return "❌ Ошибка при запросе к OpenAI. Попробуйте позже.", None

# --- 📌 Обработчики команд ---
@dp.message(Command("start"))
async def start(message: Message):
    await message.answer("👋 Привет! Напиши мне сообщение, и я передам его ассистенту OpenAI.")

@dp.message()
async def handle_message(message: Message):
    user_text = message.text
    await message.answer("🔄 Обрабатываю ваш запрос...")

    try:
        response, _ = await ask_openai(user_text)
        await message.answer(response)
    except Exception as e:
        await message.answer(f"❌ Ошибка: {e}")

# --- 📌 Запуск бота ---
async def main():
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())
