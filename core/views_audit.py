from django.contrib.auth.decorators import login_required
from django.shortcuts import render
from django.http import HttpResponse
import csv
from .models import AuditLog

@login_required
def audit_history(request):
    logs = AuditLog.objects.filter(user=request.user).order_by('-timestamp')[:100]
    return render(request, 'audit_history.html', {'logs': logs})

@login_required
def download_audit_log(request):
    logs = AuditLog.objects.filter(user=request.user).order_by('-timestamp')
    response = HttpResponse(content_type='text/csv')
    response['Content-Disposition'] = 'attachment; filename="audit_log.csv"'
    writer = csv.writer(response)
    writer.writerow(['Time', 'Action', 'Object', 'Details'])
    for log in logs:
        writer.writerow([
            log.timestamp.strftime('%Y-%m-%d %H:%M'),
            log.get_action_display(),
            f"{log.object_type} #{log.object_id}",
            log.extra_data or ''
        ])
    return response
