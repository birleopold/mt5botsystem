# Deployment Instructions for MetaTrader5 SaaS Django Project

## 1. Prerequisites
- Python 3.10 or greater
- pip (Python package manager)
- PostgreSQL or SQLite (default: SQLite)
- Node.js & npm (if using frontend build tools)
- [Recommended] Virtual environment tool (venv, virtualenv)

## 2. Environment Setup
1. Clone the repository:
   ```sh
   git clone <your-repo-url>
   cd metatrader5
   ```
2. Create and activate a virtual environment:
   ```sh
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```
3. Install dependencies:
   ```sh
   pip install -r requirements.txt
   ```

## 3. Configuration
1. Copy `.env.example` to `.env` and set your environment variables (SECRET_KEY, database, email, etc.):
   ```sh
   cp .env.example .env
   ```
2. Update `settings.py` to use environment variables (already configured for email, Stripe, etc.).

## 4. Database Migration
```sh
python manage.py migrate
```

## 5. Create a Superuser
```sh
python manage.py createsuperuser
```

## 6. Collect Static Files
```sh
python manage.py collectstatic
```

## 7. Running the Server
```sh
python manage.py runserver
```

## 8. Production Deployment
- Use Gunicorn or uWSGI behind Nginx or Apache.
- Set `DEBUG = False` in `settings.py` and configure `ALLOWED_HOSTS`.
- Use a secure database (PostgreSQL recommended).
- Set up HTTPS (SSL/TLS) for your domain.
- Set up a process manager (systemd, supervisor).
- Use a secure SMTP server for emails.

## 9. Best Practices
- Never commit secrets or credentials to version control.
- Use environment variables for all sensitive settings.
- Regularly update dependencies and apply security patches.
- Enable logging and monitor error logs.
- Test email functionality in staging before production.
- Back up your database and static/media files regularly.
- Use strong, unique passwords for all admin accounts.

## 10. Useful Commands
- Run tests: `python manage.py test`
- Check for security issues: `python manage.py check --deploy`
- Lint code: `flake8 core/`

---
For more information, see the README.md file.
