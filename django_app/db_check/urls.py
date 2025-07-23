from django.urls import path
from .views import db_health_check

urlpatterns = [
    path('db-check/', db_health_check),
]
