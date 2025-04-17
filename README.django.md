
INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
'rest_framework_simplejwt',
    "rest_framework",
    "apis",
]

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),
    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticated',  # All routes require authentication
    ),
}



<!-- SHELL COMMANDS -->
 from django.contrib.auth.models import User
User.objects.create_user(username='admin2', password='mypassword123', email='admin@example.com')


<!-- ROOT URLS -->
urlpatterns = [
    path("admin/", admin.site.urls),
    path('api/', include('apis.urls')),  # Includes app-level URLs
    path('api/login/', PublicTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
  
]

<!-- PRJ URLS  -->
urlpatterns = [
    path('login/', PublicTokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('sample/', SampleProtectedView.as_view(), name='sample'),
    path('another/', AnotherProtectedView.as_view(), name='another'),
]

<!-- PRJ VIEWS -->
from rest_framework_simplejwt.views import TokenObtainPairView
from rest_framework.permissions import AllowAny

class PublicTokenObtainPairView(TokenObtainPairView):
    permission_classes = [AllowAny]  # Allow unauthenticated access
#


from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated

class SampleProtectedView(APIView):
    permission_classes = [IsAuthenticated]  # Redundant due to global setting, but explicit

    def get(self, request):
        return Response({"message": f"Hello, {request.user.username}! You are authenticated."})

class AnotherProtectedView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        return Response({"message": "This is a protected POST endpoint."})

