#!/usr/bin/env python3
"""
Helper script to detect "No data" text in Ray dashboard using browser automation.
This checks the Cluster Utilization panel for "No data" message.
"""

import sys
import time

def detect_playwright(url):
    """Detect 'No data' using Playwright."""
    try:
        from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
        
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()
            
            try:
                page.goto(url, wait_until="networkidle", timeout=30000)
                time.sleep(3)  # Wait for dashboard to load
                
                # Look for "No data" text in the page
                # Ray dashboard typically shows this in Cluster Utilization panel
                page_text = page.content().lower()
                body_text = page.locator("body").inner_text().lower()
                
                # Check for various "no data" indicators
                no_data_patterns = [
                    "no data",
                    "no data available",
                    "no metrics",
                    "no data to display",
                ]
                
                for pattern in no_data_patterns:
                    if pattern in body_text or pattern in page_text:
                        browser.close()
                        return True
                
                # Also check for specific Ray dashboard elements
                try:
                    # Look for Cluster Utilization panel
                    cluster_util = page.locator("text=/cluster.*utilization/i").first
                    if cluster_util.count() > 0:
                        util_text = cluster_util.inner_text().lower()
                        if any(pattern in util_text for pattern in no_data_patterns):
                            browser.close()
                            return True
                except Exception:
                    pass
                
                browser.close()
                return False
                
            except PlaywrightTimeout:
                browser.close()
                print(f"⚠ Timeout loading page: {url}", file=sys.stderr)
                return None
                
    except ImportError:
        return None
    except Exception as e:
        print(f"⚠ Playwright detection failed: {e}", file=sys.stderr)
        return None

def detect_selenium(url):
    """Detect 'No data' using Selenium."""
    try:
        from selenium import webdriver
        from selenium.webdriver.chrome.options import Options
        from selenium.webdriver.common.by import By
        from selenium.webdriver.support.ui import WebDriverWait
        from selenium.webdriver.support import expected_conditions as EC
        
        chrome_options = Options()
        chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--window-size=1920,1080")
        
        driver = webdriver.Chrome(options=chrome_options)
        driver.get(url)
        
        try:
            # Wait for page to load
            WebDriverWait(driver, 10).until(
                EC.presence_of_element_located((By.TAG_NAME, "body"))
            )
            time.sleep(3)  # Additional wait for dynamic content
            
            # Get page text
            body_text = driver.find_element(By.TAG_NAME, "body").text.lower()
            
            # Check for "no data" patterns
            no_data_patterns = [
                "no data",
                "no data available",
                "no metrics",
                "no data to display",
            ]
            
            for pattern in no_data_patterns:
                if pattern in body_text:
                    driver.quit()
                    return True
            
            driver.quit()
            return False
            
        except Exception as e:
            driver.quit()
            print(f"⚠ Selenium detection error: {e}", file=sys.stderr)
            return None
            
    except ImportError:
        return None
    except Exception as e:
        print(f"⚠ Selenium detection failed: {e}", file=sys.stderr)
        return None

def detect_curl(url):
    """Basic detection using curl (fallback)."""
    try:
        import subprocess
        import re
        
        result = subprocess.run(
            ["curl", "-s", url],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            return None
        
        content_lower = result.stdout.lower()
        
        # Look for "no data" in HTML
        no_data_patterns = [
            r"no\s+data",
            r"no\s+data\s+available",
            r"no\s+metrics",
        ]
        
        for pattern in no_data_patterns:
            if re.search(pattern, content_lower):
                return True
        
        return False
        
    except Exception as e:
        print(f"⚠ Curl detection failed: {e}", file=sys.stderr)
        return None

def main():
    if len(sys.argv) < 2:
        print("Usage: detect_no_data_browser.py <url>")
        sys.exit(1)
    
    url = sys.argv[1]
    
    # Try different methods
    result = detect_playwright(url)
    if result is not None:
        sys.exit(0 if result else 1)
    
    result = detect_selenium(url)
    if result is not None:
        sys.exit(0 if result else 1)
    
    result = detect_curl(url)
    if result is not None:
        sys.exit(0 if result else 1)
    
    # If all methods failed
    print("✗ Could not detect 'No data' (no browser tools available)", file=sys.stderr)
    sys.exit(2)

if __name__ == "__main__":
    main()

