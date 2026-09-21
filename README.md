# ChatGPT Desktop Sound Notifier

A small PowerShell script for Windows that plays a custom WAV sound when the ChatGPT desktop app finishes generating a response.

Useful if you often send a message to ChatGPT, switch to another app with Alt+Tab, and want to hear when the answer is ready.

## Features

- Works with the ChatGPT desktop app on Windows
- Detects when a message is sent
- Detects when ChatGPT starts and finishes responding
- Plays your own `sound.wav`
- Works while switching to another window with Alt+Tab
- No OpenAI API required
- No installation required

## How it works

The script uses Windows UI Automation to monitor the ChatGPT desktop interface.

It watches for the ChatGPT generation state and plays a sound after the response is finished.

## Requirements

- Windows
- ChatGPT desktop app
- PowerShell
- A WAV sound file

## Installation

1. Create a folder, for example:

   `C:\ChatGPT-Sound`

2. Put these files inside:

   - `chatgpt-sound.ps1`
   - `sound.wav`

3. Open PowerShell.

4. Run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\ChatGPT-Sound\chatgpt-sound.ps1"
