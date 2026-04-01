# power_save
Power monitoring using TP-Link smart plug

100% vibe-coded with Gemini, use at your own risk

## 🚀 Features

- **Power Monitoring** Logs power use every minute to a .csv file
- **Alerting** Includes ability to send Discord webhook alert if power use exceeds a maximum (default 36 Watts)

## 📊 Output Example (power_history.csv)
| Timestamp | Wattage | Status |
| :--- | :--- | :--- |
| 2026-04-01 09:00:01 | 12 | |
| 2026-04-01 09:01:02 | 45 | |
| 2026-04-01 09:02:01 | 42 | COOLDOWN |

## 🛠️ Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/jonstaebell/power_save.git
   cd power_save
   ```

2. **Install requirements:**
   * Requires arp-scan and kasa *
   ```bash
   sudo apt update && sudo apt install arp-scan
   pipx install python-kasa
   ```

   * Note: also requires power monitoring TP-Link smart plug, such as the KP115

## ⚙️ Configuration
   Copy the sample config and fill in your details:
   ```bash
   cp .env.example .env
   ```
   Edit the .env file with your details:
- **PLUG_MAC** MAC Address of the smart plug to monitor
- **WEBHOOK_URL** Discord Webhook to be invoked if power use exceeds maximum
- **LAST_IP** Leave as 0.0.0.0, script will update when MAC Address is found

## 📖 Usage

### Standard Run
```bash
./power_check.sh
```

Optional: add argument to specify maximum wattage (exceeding will invoke the Discord webhook):
Example to alert if power exceeds 10 amps:
```bash
./power_check.sh 10
```

To never alert (e.g. if you have no Discord webhook to invoke), use high number, e.g. 999
```bash
./power_check.sh 999
```

### ⏰ Automation (Cronjob)

To keep your library updated automatically, you can schedule the script using 'cron'.

#### ⚠️Safety Warning

Do not schedule this script until you have performed a successful test from command line.

#### Setup Instructions
1. **Open your crontab editor:**
```bash
crontab -e
```

2. **Add a line at the bottom to run the script.**

**Example: Run every minute **

```bash
* * * * * /bin/bash /path/to/power_save/power_check.sh 36 >> /path/to/power_save/logs/cron.log 2>&1
```

**Troubleshooting Cron**

If the script doesn't seem to be running:

1. Check `cron_debug.log` in the logs folder for errors.

2. Ensure the paths to your folder are correct for your specific system.

3. Make sure your `.env` is in the same folder as `power_check.sh`


## 📝 Logging
The script maintains a `power_error.log` file in the logs folder, recording every batch dispatched and any API errors encountered.
Power use data is saved in a `power_save.csv` file in the logs folder.

---

## ⚠️ Disclaimer & Liability

**This project was 100% "vibe coded" in collaboration with Gemini.** While the logic is designed to be helpful, it is provided "as-is" without any warranties.

* **No Responsibility:** I take **no responsibility** for any security breaches, accidental data losses, or hardware issues resulting from the use of this script.
* **User Security:** You are solely responsible for securing your local environment. 
* **Vibe Check:** Use this script at your own risk. It was built through conversation and logic, not a formal development audit.

---

## ⚖️ License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
