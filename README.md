# ChatGPT Desktop Sound Notifier

A small PowerShell script for Windows that plays a custom WAV sound when the ChatGPT desktop app finishes generating a response.

Useful if you often send a message to ChatGPT, switch to another app with Alt+Tab, and want to hear when the answer is ready.

## Features

- Works with the ChatGPT desktop app on Windows
- Detects when a message is sent
- Detects when ChatGPT starts and finishes responding
- Plays your own `sound.wav`
- Continues monitoring while you work in another window
- No OpenAI API key required
- No installer required

## How it works

The script uses Windows UI Automation to monitor the ChatGPT desktop interface. It watches the generation state and plays a sound after the response is finished.

## Requirements

- Windows
- ChatGPT desktop app
- PowerShell
- A Windows-compatible WAV sound file

## Installation

1. Download `chatgpt-sound.ps1` from this repository.
2. Create a folder, for example:

   `C:\ChatGPT-Sound`

3. Put these files inside the folder:

   - `chatgpt-sound.ps1`
   - `sound.wav`

4. Open PowerShell and run:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\ChatGPT-Sound\chatgpt-sound.ps1"
```

5. Keep the PowerShell window open while you use ChatGPT.

## Usage

1. Start the script using the command above.
2. Use the ChatGPT desktop app normally.
3. Send a message, then switch to another application if you want.
4. When ChatGPT finishes generating the response, the script plays `sound.wav`.
5. Press `Ctrl+C` in the PowerShell window to stop the monitor.

For the most reliable behavior, send the message and switch windows using Alt+Tab.

## Custom sound

Replace `sound.wav` with any Windows-compatible WAV file. Keep the filename exactly `sound.wav` and place it in the same folder as `chatgpt-sound.ps1`.

A standard PCM WAV file is the safest choice. MP3, OGG, and other formats are not supported by this script.

## Notes

- The script depends on the current ChatGPT desktop interface and its UI Automation labels.
- A future ChatGPT desktop update may require adjustments to the detection logic.
- The script is designed for the Windows desktop app, not the browser version of ChatGPT.
- If no sound plays, confirm that `sound.wav` exists beside the script and can be opened by Windows.

## Privacy

The script runs locally on your computer. It does not require an OpenAI API key, send your prompts or responses anywhere, or include telemetry. It only inspects the local ChatGPT window state needed to detect when generation starts and finishes.

## Disclaimer

This is an unofficial community project and is not affiliated with or endorsed by OpenAI. The script is provided as-is, without warranty. Use it at your own risk.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
