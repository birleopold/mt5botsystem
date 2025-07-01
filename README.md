# MetaTrader5 SaaS Django Project

A Django-based SaaS platform for managing MetaTrader5 subscriptions, payments, and user accounts, with RESTful APIs and email notifications.

## Features
- User registration, login, and dashboard
- Subscription management (renew, cancel, activate)
- Payment integration (Stripe, Coinbase, Binance)
- Email notifications for subscription events
- REST API with authentication and throttling
- Admin dashboard (Django admin & Jazzmin)
- Social sharing and analytics events

## Tech Stack
- Python 3.10+, Django 5.2
- Django REST Framework 3.14.0
- SQLite (default) or PostgreSQL
- Stripe, Coinbase Commerce, Binance API
- Jazzmin admin theme

## Getting Started
See [DEPLOYMENT.md](./DEPLOYMENT.md) for full setup and deployment instructions.

## Configuration
- All sensitive settings (SECRET_KEY, database, email, Stripe, etc.) should be set via environment variables or a `.env` file.
- See `.env.example` for required variables.

## Running Locally
```sh
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver
```

## Running Tests
```sh
python manage.py test
```

## API Documentation
- Swagger/OpenAPI: `/swagger/`
- Redoc: `/redoc/`

## License
See [LICENSE](./LICENSE).

## Contributing
Pull requests are welcome. For major changes, open an issue first to discuss what you would like to change.

## Security
- Never commit credentials or secrets.
- Set `DEBUG = False` in production.
- Use HTTPS and secure email backends.

## Contact
For support, please open an issue or contact the maintainer.
