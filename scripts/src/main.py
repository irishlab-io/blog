import qrcode


def generate_qr_code(url, output_filename):
    print(f"Generating QR code for: {url}")

    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(url)
    qr.make(fit=True)


    img = qr.make_image(fill_color="black", back_color="white")
    img.save(output_filename)
    print(f"Successfully saved QR code to {output_filename}")


def main():
    # Replace with your actual website URL
    url = "https://irishlab.io"
    output_filename = "website_qr.png"
    generate_qr_code(url, output_filename)


if __name__ == "__main__":
    main()
