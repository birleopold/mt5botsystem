from django.shortcuts import render, get_object_or_404, redirect
from django.contrib.auth.decorators import login_required
from django.http import HttpResponse, Http404, JsonResponse
from django.core.paginator import Paginator
from django.db.models import Q
from django.contrib import messages
from django.utils import timezone

from .models_learning import LearningCategory, LearningResource, UserProgress

def learning_center(request):
    """Main learning center view showing categories and featured resources"""
    categories = LearningCategory.objects.all()
    featured_resources = LearningResource.objects.filter(featured=True)[:6]
    
    # Get user's active subscription to determine access levels
    user_subscription = None
    if request.user.is_authenticated:
        # Check if the User model has a subscriptions attribute
        if hasattr(request.user, 'subscriptions'):
            user_subscription = request.user.subscriptions.filter(is_active=True).first()
        # If not, we'll just use None for now
    
    # Get user progress for featured resources
    user_progress = {}
    if request.user.is_authenticated:
        progress_objects = UserProgress.objects.filter(
            user=request.user,
            resource__in=featured_resources
        )
        user_progress = {p.resource_id: p.progress_percent for p in progress_objects}
    
    context = {
        'categories': categories,
        'featured_resources': featured_resources,
        'user_subscription': user_subscription,
        'user_progress': user_progress,
    }
    
    return render(request, 'learning/learning_center.html', context)

def category_detail(request, slug):
    """View for a specific learning category"""
    category = get_object_or_404(LearningCategory, slug=slug)
    
    # Filter resources by search query if provided
    query = request.GET.get('q', '')
    resources = category.resources.all()
    
    if query:
        resources = resources.filter(
            Q(title__icontains=query) | 
            Q(description__icontains=query)
        )
    
    # Filter by resource type if provided
    resource_type = request.GET.get('type', '')
    if resource_type:
        resources = resources.filter(resource_type=resource_type)
    
    # Filter by access level
    access_level = request.GET.get('access', '')
    if access_level:
        resources = resources.filter(access_level=access_level)
    
    # Pagination
    paginator = Paginator(resources, 12)  # 12 resources per page
    page_number = request.GET.get('page', 1)
    resources_page = paginator.get_page(page_number)
    
    # Get user progress for these resources
    user_progress = {}
    if request.user.is_authenticated:
        progress_objects = UserProgress.objects.filter(
            user=request.user,
            resource__in=resources_page
        )
        user_progress = {p.resource_id: p.progress_percent for p in progress_objects}
    
    context = {
        'category': category,
        'resources': resources_page,
        'query': query,
        'resource_type': resource_type,
        'access_level': access_level,
        'user_progress': user_progress,
    }
    
    return render(request, 'learning/category_detail.html', context)

def resource_detail(request, slug):
    """View for a specific learning resource"""
    resource = get_object_or_404(LearningResource, slug=slug)
    
    # Check if user has access to this resource
    if not resource.is_accessible_by(request.user):
        messages.warning(request, "You need to upgrade your subscription to access this resource.")
        return redirect('learning_center')
    
    # Get or create user progress
    progress = None
    if request.user.is_authenticated:
        progress, created = UserProgress.objects.get_or_create(
            user=request.user,
            resource=resource,
            defaults={'progress_percent': 0}
        )
        
        # Update last accessed time
        progress.last_accessed = timezone.now()
        progress.save()
        
        # Increment view count only once per session
        if f'viewed_resource_{resource.id}' not in request.session:
            resource.view_count += 1
            resource.save()
            request.session[f'viewed_resource_{resource.id}'] = True
    
    # Get related resources from the same category
    related_resources = LearningResource.objects.filter(
        category=resource.category
    ).exclude(id=resource.id)[:4]
    
    context = {
        'resource': resource,
        'progress': progress,
        'related_resources': related_resources,
    }
    
    return render(request, 'learning/resource_detail.html', context)

@login_required
def update_progress(request, resource_id):
    """AJAX endpoint to update user progress"""
    if request.method != 'POST':
        return JsonResponse({'error': 'Only POST requests allowed'}, status=405)
    
    resource = get_object_or_404(LearningResource, id=resource_id)
    
    # Check if user has access
    if not resource.is_accessible_by(request.user):
        return JsonResponse({'error': 'Access denied'}, status=403)
    
    try:
        percent = int(request.POST.get('percent', 0))
        completed = request.POST.get('completed') == 'true'
        
        # Validate percent
        if percent < 0 or percent > 100:
            return JsonResponse({'error': 'Invalid progress percentage'}, status=400)
        
        # Update or create progress
        progress, created = UserProgress.objects.get_or_create(
            user=request.user,
            resource=resource,
            defaults={
                'progress_percent': percent,
                'completed': completed
            }
        )
        
        if not created:
            progress.progress_percent = percent
            progress.completed = completed
            progress.save()
        
        return JsonResponse({
            'success': True,
            'progress': percent,
            'completed': completed
        })
        
    except Exception as e:
        return JsonResponse({'error': str(e)}, status=400)

@login_required
def my_learning(request):
    """View for user's learning dashboard"""
    # Get resources the user has interacted with
    progress_items = UserProgress.objects.filter(user=request.user).order_by('-last_accessed')
    
    # Get in-progress and completed resources
    in_progress = [p for p in progress_items if 0 < p.progress_percent < 100]
    completed = [p for p in progress_items if p.completed or p.progress_percent == 100]
    
    # Get recommended resources (not started yet)
    started_resource_ids = [p.resource_id for p in progress_items]
    
    # Get user's subscription to determine accessible resources
    subscription = None
    if hasattr(request.user, 'subscriptions'):
        subscription = request.user.subscriptions.filter(is_active=True).first()
    
    # Determine access level based on subscription
    if subscription and hasattr(subscription, 'plan'):
        plan_name = subscription.plan.name.lower()
        if 'pro' in plan_name:
            access_levels = ['free', 'basic', 'premium', 'pro']
        elif 'premium' in plan_name:
            access_levels = ['free', 'basic', 'premium']
        elif 'basic' in plan_name:
            access_levels = ['free', 'basic']
        else:
            access_levels = ['free']
    else:
        access_levels = ['free']
    
    # Get recommended resources
    recommended = LearningResource.objects.filter(
        access_level__in=access_levels
    ).exclude(
        id__in=started_resource_ids
    ).order_by('-featured', '-created_at')[:6]
    
    context = {
        'in_progress': in_progress,
        'completed': completed,
        'recommended': recommended,
        'subscription': subscription,
    }
    
    return render(request, 'learning/my_learning.html', context)

def download_resource(request, resource_id):
    """Handle downloads of resource files"""
    resource = get_object_or_404(LearningResource, id=resource_id)
    
    # Check if user has access
    if not resource.is_accessible_by(request.user):
        messages.warning(request, "You need to upgrade your subscription to download this resource.")
        return redirect('learning_center')
    
    # Check if resource has a file
    if not resource.file:
        raise Http404("No file associated with this resource")
    
    # Track download in user progress
    if request.user.is_authenticated:
        progress, created = UserProgress.objects.get_or_create(
            user=request.user,
            resource=resource
        )
        progress.last_accessed = timezone.now()
        progress.save()
    
    # Serve the file
    response = HttpResponse(resource.file.read(), content_type='application/octet-stream')
    response['Content-Disposition'] = f'attachment; filename="{resource.file.name.split("/")[-1]}"'
    return response
