import os
import sys

from main import generate_qr_code


# Add src directory to sys.path to allow importing main
sys.path.append(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'src'))

def test_generate_qr_code():
    url = "https://example.com"
    filename = "test_qr.png"

    # Ensure file doesn't exist before test
    if os.path.exists(filename):
        os.remove(filename)

    try:
        generate_qr_code(url, filename)

        # Check if file was created
        assert os.path.exists(filename), "QR code image file was not created"

        # Optional: Check file size is not empty
        assert os.path.getsize(filename) > 0, "QR code image file is empty"

    finally:
        # Cleanup
        if os.path.exists(filename):
            os.remove(filename)
