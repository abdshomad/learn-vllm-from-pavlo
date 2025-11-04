#!/usr/bin/env python3
"""
Helper script to take browser screenshots using available tools.
This can be called from bash scripts to capture screenshots of web pages.
"""

import sys
import os
import time
import subprocess
from pathlib import Path

def take_screenshot_playwright(url, output_path, description=""):
    """Take screenshot using Playwright if available."""
    try:
        import playwright
        from playwright.sync_api import sync_playwright
        
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()
            page.goto(url, wait_until="networkidle", timeout=30000)
            time.sleep(2)  # Wait for any dynamic content
            page.screenshot(path=output_path, full_page=True)
            browser.close()
        
        print(f"✓ Screenshot saved: {output_path}")
        return True
    except ImportError:
        return False
    except Exception as e:
        print(f"⚠ Playwright screenshot failed: {e}", file=sys.stderr)
        return False

def take_screenshot_selenium(url, output_path, description=""):
    """Take screenshot using Selenium if available."""
    try:
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.chrome.service import Service
        
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        chrome_options = Options()
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--window-size=1920,1080")
        
        driver = webdriver.Chrome(options=chrome_options)
        driver.get(url)
        time.sleep(3)  # Wait for page to load
        driver.save_screenshot(output_path)
        driver.quit()
        
        print(f"✓ Screenshot saved: {output_path}")
        return True
    except ImportError:
        return False
    except Exception as e:
        print(f"⚠ Selenium screenshot failed: {e}", file=sys.stderr)
        return False

def take_screenshot_wkhtmltopdf(url, output_path, description=""):
    """Take screenshot using wkhtmltopdf/wkhtmltoimage if available."""
    try:
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        # Try wkhtmltoimage first
        result = subprocess.run(
            ["wkhtmltoimage", "--width", "1920", url, output_path],
            capture_output=True,
            timeout=30
        )
        
        if result.returncode == 0 and os.path.exists(output_path):
            print(f"✓ Screenshot saved: {output_path}")
            return True
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    except Exception as e:
        print(f"⚠ wkhtmltoimage screenshot failed: {e}", file=sys.stderr)
    
    return False

def main():
    if len(sys.argv) < 3:
        print("Usage: take_browser_screenshot.py <url> <output_path> [description]")
        sys.exit(1)
    
    url = sys.argv[1]
    output_path = sys.argv[2]
    description = sys.argv[3] if len(sys.argv) > 3 else ""
    
    print(f"Taking screenshot: {description or url}")
    print(f"URL: {url}")
    print(f"Output: {output_path}")
    
    # Try different methods in order of preference
    if take_screenshot_playwright(url, output_path, description):
        sys.exit(0)
    
    if take_screenshot_selenium(url, output_path, description):
        sys.exit(0)
    
    if take_screenshot_wkhtmltopdf(url, output_path, description):
        sys.exit(0)
    
    # If all methods failed, print error
    print("✗ No screenshot tool available (tried: playwright, selenium, wkhtmltoimage)", file=sys.stderr)
    print("  Install one of: playwright, selenium, wkhtmltopdf", file=sys.stderr)
    sys.exit(1)

if __name__ == "__main__":
    main()

