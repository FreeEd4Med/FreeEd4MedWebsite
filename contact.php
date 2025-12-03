<?php
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $name    = strip_tags(trim($_POST["name"]));
    $email   = filter_var(trim($_POST["email"]), FILTER_SANITIZE_EMAIL);
    $message = trim($_POST["message"]);
    $captcha = $_POST["g-recaptcha-response"];

    if (empty($name) || !filter_var($email, FILTER_VALIDATE_EMAIL) || empty($message)) {
        http_response_code(400);
        echo "Invalid input.";
        exit;
    }

    // Verify reCAPTCHA
    $secretKey = "6LcB_4orAAAAAOo5PhM1ycKhpHHrWcn3vJ0abDjt";  // Still valid but can be replaced with newer if desired
    $response = file_get_contents("https://www.google.com/recaptcha/api/siteverify?secret=" . $secretKey . "&response=" . $captcha);
    $responseKeys = json_decode($response, true);
    if (!$responseKeys["success"]) {
        http_response_code(403);
        echo "Captcha validation failed.";
        exit;
    }

    $recipient = "contact@freeed4med.org";
    $subject = "FreeEd4Med Contact Form from $name";
    $email_content = "Name: $name\nEmail: $email\n\nMessage:\n$message";
    $headers = "From: $name <$email>";

    if (mail($recipient, $subject, $email_content, $headers)) {
        // Success: show confirmation page
        echo <<<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Thank You – FreeEd4Med</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <link href="style.css" rel="stylesheet" />
  <style>
    body {
      font-family: Arial, sans-serif;
      text-align: center;
      padding: 3rem 1rem;
      background-color: #f7f7fa;
      color: #333;
    }
    h1 {
      font-size: 2rem;
      color: #4a148c;
    }
    p {
      font-size: 1.2rem;
      margin-top: 1rem;
    }
    .nav-links a {
      margin: 0 10px;
      text-decoration: none;
      color: #4a148c;
      font-weight: bold;
    }
    .nav-links {
      margin-top: 2rem;
    }
  </style>
</head>
<body>
  <h1>Thank you for reaching out to FreeEd4Med!</h1>
  <p>Your message has been sent successfully. We appreciate your time and will get back to you as soon as possible.</p>

  <div class="nav-links">
    <a href="index.html">Home</a> |
    <a href="education.html">Healthcare Education</a> |
    <a href="public.html">Public Info</a> |
    <a href="donate.html">Donate</a> |
    <a href="about.html">About Us</a>
  </div>
</body>
</html>
HTML;
        http_response_code(200);
    } else {
        http_response_code(500);
        echo "Mail delivery failed.";
    }
} else {
    http_response_code(403);
    echo "Invalid request.";
}
?>
