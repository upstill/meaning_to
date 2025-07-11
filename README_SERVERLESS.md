# Serverless API Deployment

This approach uses Vercel serverless functions to handle Supabase operations server-side, keeping your secrets secure.

## How It Works

1. **Client-side**: Your Flutter app makes HTTP requests to `/api` endpoint
2. **Server-side**: Vercel serverless function handles Supabase operations
3. **Security**: Supabase credentials never leave the server

## Files Created

### API Layer
- `api/index.js` - Serverless function handling all Supabase operations
- `api/package.json` - Dependencies for the API

### Client Layer
- `lib/utils/api_client.dart` - Client-side API wrapper
- `lib/utils/cache_manager_api.dart` - Example cache manager using API

### Deployment
- `vercel.json` - Vercel configuration
- `build.sh` - Build script for Flutter web

## Environment Variables

Set these in your Vercel project settings:

```
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key
```

**Important**: Use the service role key, not the anon key, for server-side operations.

## Usage Example

### Before (Direct Supabase)
```dart
// Direct Supabase call - exposes credentials in client
await supabase
    .from('Tasks')
    .update({'suggestible_at': newTime.toIso8601String()})
    .eq('id', taskId)
    .eq('owner_id', userId);
```

### After (API Client)
```dart
// API call - credentials stay on server
await ApiClient.updateTask(taskId.toString(), {
  'suggestible_at': newTime.toIso8601String(),
});
```

## Migration Steps

1. **Replace direct Supabase calls** with `ApiClient` calls
2. **Update cache managers** to use API instead of direct database access
3. **Test thoroughly** to ensure all operations work correctly

## Benefits

- ✅ **Secure**: Credentials never exposed in client-side code
- ✅ **Scalable**: Serverless functions auto-scale
- ✅ **Reliable**: Vercel handles infrastructure
- ✅ **Simple**: No complex build configurations needed

## API Endpoints

The serverless function supports these actions:

- `getTasks` - Get all tasks for current user
- `updateTask` - Update a specific task
- `createTask` - Create a new task
- `deleteTask` - Delete a task
- `getCategories` - Get all categories for current user
- `createCategory` - Create a new category
- `deleteCategory` - Delete a category

## Deployment

1. Push your code to GitHub
2. Connect your repository to Vercel
3. Set environment variables in Vercel dashboard
4. Deploy!

The serverless function will be automatically deployed alongside your Flutter web app. 