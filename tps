import logging
import os
import threading
import tkinter as tk
from tkinter import messagebox
import sys
import winreg
from pathlib import Path
import webbrowser
from datetime import datetime
# Essential Libraries
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from escpos.printer import Win32Raw, Dummy
from PIL import Image, ImageOps, ImageEnhance, ImageTk
import win32print
from html2image import Html2Image
import uvicorn
from pystray import Icon, Menu, MenuItem
import subprocess

# --- INSTALLATION CMD ---
# python -m PyInstaller "zencriosTPS.py" --onedir --windowed --icon=app.ico --version-file=version.txt --add-data "app.ico;." --hidden-import=win32print --hidden-import=pystray._win32 --hidden-import=escpos.printer.win32raw --collect-all escpos --collect-all pystray --collect-all PIL --collect-all html2image
# --- INSTALLATION CMD ---

 
# --- Configuration & Setup ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger("ThermalPrinterAPI")

app = FastAPI(title="Thermal Printer Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

SERVICE_RUNNING = True

# FLUX FIX: Global singleton to prevent "headless browser" process leaks
HTI_INSTANCE = Html2Image(
    browser_executable="C:/Program Files/Google/Chrome/Application/chrome.exe",
    custom_flags=[
        '--no-sandbox',
        '--disable-gpu',
        '--hide-scrollbars',
        '--disable-dev-shm-usage',
        '--log-level=3'
    ]
)


# --- Models ---
class PrintRequest(BaseModel):
    printerName: str
    html: str 

# --- Core Logic ---
class PrinterService:
    @staticmethod
    def get_printer(printer_name: str):
        try:
            return Win32Raw(printer_name)
        except Exception as e:
            logger.error(f"Hardware Connection Error: {e}")
            return Dummy()

    @staticmethod
    def process_and_print(printer_name: str, html: str):
        if not SERVICE_RUNNING:
            logger.warning("Job ignored: Service is stopped.")
            return

        temp_filename = f"print_{threading.get_ident()}.png"
        printer = None
        
        try:
            logger.info(f"Processing job for: {printer_name}")
            width_px = 576 
            full_html = f"""<div style="width: {width_px}px; background-color: white; padding: 5px; margin: 0;">{html}</div>"""
            
            # Use singleton HTI to save the image
            HTI_INSTANCE.screenshot(html_str=full_html, save_as=temp_filename, size=(width_px, 1500))

            if not os.path.exists(temp_filename):
                logger.error("HTI failed to generate image.")
                return

            with Image.open(temp_filename) as img:
                img = ImageOps.grayscale(img)
                enhancer = ImageEnhance.Contrast(img)
                img = enhancer.enhance(4.0)
                bbox = ImageOps.invert(img).getbbox()
                if bbox: img = img.crop(bbox)
                img = img.convert('1')

                printer = PrinterService.get_printer(printer_name)
                printer.text("\n") 
                printer.image(img)
                printer.text("\n" * 4)
                printer.cut()
                
            logger.info("Print job completed.")
            
        except Exception as e:
            logger.error(f"Print Logic Error: {str(e)}")
        finally:
            if os.path.exists(temp_filename):
                try: os.remove(temp_filename)
                except: pass
            if printer and hasattr(printer, 'close'):
                printer.close()




# --- API Endpoints ---

@app.get("/")
async def root():
    status = "RUNNING" if SERVICE_RUNNING else "STOPPED"
    return {"message": "Thermal Printer Service is Online", "status": status, "port": 7070}

@app.post("/print")
async def print_receipt(request: PrintRequest, background_tasks: BackgroundTasks):
    if not SERVICE_RUNNING:
        raise HTTPException(status_code=503, detail="Service is currently stopped")
    background_tasks.add_task(PrinterService.process_and_print, request.printerName, request.html)
    return {"status": "success", "message": "Job queued"}

@app.get("/health")
async def health_check(printerName: str):
    try:
        phandle = win32print.OpenPrinter(printerName)
        win32print.ClosePrinter(phandle)
        return {"status": "online" if SERVICE_RUNNING else "stopped", "printer": printerName}
    except Exception:
        return {"status": "offline", "printer": printerName}

# ... (Keep all your existing imports and API logic exactly as they are) ...

# --- Improved UI Widgets ---

class ModernButton(tk.Canvas):
    """A high-fidelity rounded button with hover animations."""
    def __init__(self, parent, text, color, hover_color, command, width=150, height=40):
        super().__init__(parent, width=width, height=height, bg=parent['bg'], highlightthickness=0, cursor="hand2")
        self.command = command
        self.color = color
        self.hover_color = hover_color
        
        # Draw Shadow/Border effect
        self.rect = self._create_round_rect(0, 0, width, height, 12, fill=color)
        self.text_id = self.create_text(width/2, height/2, text=text, fill="white", font=("Segoe UI Semibold", 10))

        self.bind("<Button-1>", lambda e: self.command())
        self.bind("<Enter>", self._on_enter)
        self.bind("<Leave>", self._on_leave)

    def _create_round_rect(self, x1, y1, x2, y2, r, **kwargs):
        points = [x1+r, y1, x1+r, y1, x2-r, y1, x2-r, y1, x2, y1, x2, y1+r, x2, y1+r, x2, y2-r, x2, y2-r, x2, y2, x2-r, y2, x2-r, y2, x1+r, y2, x1+r, y2, x1, y2, x1, y2-r, x1, y2-r, x1, y1+r, x1, y1+r, x1, y1]
        return self.create_polygon(points, **kwargs, smooth=True)

    def _on_enter(self, e):
        self.itemconfig(self.rect, fill=self.hover_color)
        
    def _on_leave(self, e):
        self.itemconfig(self.rect, fill=self.color)

# --- Improved GUI and System Tray ---

# --- Improved GUI and System Tray ---

def get_resource_path(relative_path):
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.abspath("."), relative_path)

def resource_path(relative_path: str) -> str:
    """
    Works in dev + PyInstaller EXE.
    """
    try:
        base_path = sys._MEIPASS
    except Exception:
        base_path = Path(__file__).resolve().parent

    return str(Path(base_path) / relative_path)


class TrayApp:
    def __init__(self):
        self.app_name = "Thermal Printer Service"
        self.icon_path = resource_path("app.ico")
        self.logo_path = resource_path("app.ico")

        
        self.root = None
        self.tray_icon = None
        self.logo_img_tk = None  # Reference to prevent garbage collection
        
        self.colors = {
            "bg": "#FFFFFF",
            "card_bg": "#F8F9FA",
            "accent": "#0078D4",
            "text_main": "#1A1A1A",
            "text_sub": "#666666",
            "border": "#EEEEEE",
            "success": "#28A745"
        }
        
        self.version_info = {
            "app": "v2.1.0",
            "build": "26H02TP",
            "company": "Zencrios",
            "website": "www.zencrios.com"
        }

    def show_about(self):
        if self.root is not None:
            try:
                self.root.deiconify()
                self.root.lift()
                return
            except tk.TclError:
                self.root = None

        self.root = tk.Tk()
        self.root.title(f"About {self.app_name}")
        self.root.geometry("420x520")
        self.root.configure(bg=self.colors["bg"])
        self.root.resizable(False, False)
        self.root.protocol("WM_DELETE_WINDOW", self.root.withdraw)

        if os.path.exists(self.logo_path):
            pil_img = Image.open(self.logo_path)
            self.title_icon = ImageTk.PhotoImage(pil_img.resize((32, 32), Image.Resampling.LANCZOS))
            self.root.iconphoto(False, self.title_icon)
            self.logo_img_tk = ImageTk.PhotoImage(pil_img.resize((80, 80), Image.Resampling.LANCZOS))
        else:
            self.logo_img_tk = None

        header = tk.Frame(self.root, bg=self.colors["bg"], pady=20)
        header.pack(fill="x")

        if os.path.exists(self.logo_path):
            # Load and Resize explicitly to 80x80
            pil_img = Image.open(self.logo_path)
            pil_img = pil_img.resize((80, 80), Image.Resampling.LANCZOS)
            
            self.logo_img_tk = ImageTk.PhotoImage(pil_img)
            
            logo_label = tk.Label(header, image=self.logo_img_tk, bg=self.colors["bg"])
            logo_label.pack()
        else:
            # Fallback if no logo file exists
            logo_label = tk.Label(header, text="Z", font=("Segoe UI", 32, "bold"), 
                                 fg="white", bg=self.colors["accent"], width=2, height=1)
            logo_label.pack()

        tk.Label(header, text=self.app_name, font=("Segoe UI Variable Display", 16, "bold"), 
                 bg=self.colors["bg"], fg=self.colors["text_main"]).pack(pady=(10, 0))
        
        # --- App Description ---
        desc_frame = tk.Frame(self.root, bg=self.colors["bg"], padx=40)
        desc_frame.pack(fill="x")
        
        description = (
            "This utility allows your business software to communicate "
            "directly with your thermal receipt printer. It runs quietly "
            "in the background to ensure fast and reliable printing."
        )
        tk.Label(desc_frame, text=description, font=("Segoe UI", 9), 
                 bg=self.colors["bg"], fg=self.colors["text_sub"], wraplength=340, justify="center").pack()

        # --- Metadata Card ---
        card = tk.Frame(self.root, bg=self.colors["card_bg"], highlightbackground=self.colors["border"], 
                        highlightthickness=1, padx=20, pady=15)
        card.pack(fill="x", padx=40, pady=20)

        def _row(label, value, is_link=False):
            f = tk.Frame(card, bg=self.colors["card_bg"])
            f.pack(fill="x", pady=3)
            
            tk.Label(f, text=label, font=("Segoe UI", 8), 
                     bg=self.colors["card_bg"], fg=self.colors["text_sub"]).pack(side="left")
            
            # Create the value label
            val_label = tk.Label(f, text=value, font=("Segoe UI Semibold", 8), 
                                 bg=self.colors["card_bg"])
            
            if is_link:
                # Style as a clickable link
                val_label.configure(fg=self.colors["accent"], cursor="hand2")
                # Bind the click event
                val_label.bind("<Button-1>", lambda e: webbrowser.open_new_tab(f"https://{value}"))
            else:
                val_label.configure(fg=self.colors["text_main"])
                
            val_label.pack(side="right")
        _row("App Version", self.version_info["app"])
        _row("Build Version", self.version_info["build"])
        _row("Provider", self.version_info["company"])
        _row("Website", self.version_info["website"], is_link=True)
        
        # --- Action Buttons ---
        btn_frame = tk.Frame(self.root, bg=self.colors["bg"])
        btn_frame.pack(side="bottom", pady=(0, 20))
        
        ModernButton(btn_frame, "Close", "#444444", "#333333", self.root.withdraw, width=120).pack(side="left", padx=5)
        ModernButton(btn_frame, "Exit Service", "#D13438", "#A4262C", self.confirm_exit, width=120).pack(side="left", padx=5)

        tk.Label(self.root, text=f"Copyright © 2025 - {datetime.now().year} {self.version_info['company']}. All rights reserved.", font=("Segoe UI", 8), 
                 bg=self.colors["bg"], fg="#A0A0A0").pack(side="bottom", pady=5)

        self.root.mainloop()

    # ... (Keep confirm_exit, run_server, and run methods exactly as they are) ...

    def confirm_exit(self):
        """Thread-safe application shutdown."""
        def safe_shutdown():
            if messagebox.askyesno("Exit Confirmation", "Shutting down will stop all remote printing. Proceed?"):
                if self.root: self.root.destroy()
                if self.tray_icon: self.tray_icon.stop()
                os._exit(0)
        
        if self.root:
            self.root.after(0, safe_shutdown)
        else:
            temp_root = tk.Tk()
            temp_root.withdraw()
            safe_shutdown()

    # def run_server(self):
    #     # uvicorn.run(app, host="127.0.0.1", port=7070, log_level="error", access_log=False)
    #     try:
    #         uvicorn.run(app, host="127.0.0.1", port=7070, log_level="error")
    #     except Exception as e:
    #         if self.tray_icon:
    #             self.tray_icon.notify("Server crashed", str(e))

    def run_server(self):
        import asyncio
        import uvicorn

        config = uvicorn.Config(
            app,
            host="127.0.0.1",
            port=7070,
            log_level="error",
            loop="asyncio",
            reload=False
        )

        server = uvicorn.Server(config)
        asyncio.run(server.serve())



    def run(self):
        # Start FastAPI server in background
        threading.Thread(target=self.run_server, daemon=True).start()

        # Safe icon loading
        try:
            if os.path.exists(self.icon_path):
                image = Image.open(self.icon_path)
            else:
                image = Image.new("RGB", (64, 64), (0, 120, 212))
        except Exception as e:
            logger.error(f"Icon load failed: {e}")
            image = Image.new("RGB", (64, 64), (0, 120, 212))

        # Tray menu
        menu = Menu(
            MenuItem("Open Dashboard", self.show_about, default=True),
            MenuItem("Exit", self.confirm_exit)
        )

        # Create tray icon
        self.tray_icon = Icon(self.app_name, image, menu=menu)

        # Show startup notification AFTER tray initialized
        def notify_start():
            try:
                self.tray_icon.notify(
                    "Thermal Printer Service v2.1.0 started",
                    "Zencrios"
                )
            except Exception as e:
                logger.warning(f"Tray notification failed: {e}")

        # Delay notification slightly for reliability
        threading.Timer(2, notify_start).start()

        # Run tray loop
        self.tray_icon.run()



# --- Windows Management ---

class AppManager:
    @staticmethod
    def get_resource_path():
        if getattr(sys, 'frozen', False):
            return Path(sys.executable).resolve()
        return Path(sys.argv[0]).resolve()

    @staticmethod
    def exe_path():
        if getattr(sys, 'frozen', False):
            return Path(sys.executable).resolve()
        return Path(sys.argv[0]).resolve()

    @staticmethod
    def setup_autostart(enabled=True):
        app_name = "ThermalPrinterService"
        exe_path = f'"{AppManager.exe_path()}"'
        key_path = r"Software\Microsoft\Windows\CurrentVersion\Run"
        
        try:
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path, 0, winreg.KEY_SET_VALUE)
            if enabled:
                winreg.SetValueEx(key, app_name, 0, winreg.REG_SZ, exe_path)
            else:
                try: winreg.DeleteValue(key, app_name)
                except FileNotFoundError: pass
            winreg.CloseKey(key)
        except Exception as e:
            logger.error(f"Autostart Error: {e}")

    @staticmethod
    def setup_cmd_alias():
        exe_dir = str(AppManager.get_resource_path().parent)
        try:
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_ALL_ACCESS)
            try:
                current_path, _ = winreg.QueryValueEx(key, "Path")
            except FileNotFoundError:
                current_path = ""

            if exe_dir not in current_path:
                new_path = f"{current_path};{exe_dir}" if current_path else exe_dir
                winreg.SetValueEx(key, "Path", 0, winreg.REG_EXPAND_SZ, new_path)
            winreg.CloseKey(key)
        except Exception as e:
            logger.error(f"PATH Error: {e}")

if __name__ == "__main__":
    AppManager.setup_autostart(True)
    AppManager.setup_cmd_alias()
    
    tray = TrayApp()
    tray.run()
