from django.http import JsonResponse
from django.db import connections
from django.db.utils import OperationalError

def db_health_check(request):
    try:
        connections['default'].cursor()
        return JsonResponse({'status': 'ok'})
    except OperationalError:
        return JsonResponse({'status': 'error'}, status=500)
