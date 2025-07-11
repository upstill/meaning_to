// Vercel serverless function for handling Supabase operations
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY

const supabase = createClient(supabaseUrl, supabaseServiceKey)

export default async function handler(req, res) {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization')

  if (req.method === 'OPTIONS') {
    res.status(200).end()
    return
  }

  try {
    const { action, data, userId } = req.body

    switch (action) {
      case 'updateTask':
        const { taskId, updates } = data
        const { data: result, error } = await supabase
          .from('Tasks')
          .update(updates)
          .eq('id', taskId)
          .eq('owner_id', userId)
          .select()
        
        if (error) throw error
        res.json({ success: true, data: result })
        break

      case 'getTasks':
        const { data: tasks, error: tasksError } = await supabase
          .from('Tasks')
          .select('*')
          .eq('owner_id', userId)
          .order('created_at', { ascending: false })
        
        if (tasksError) throw tasksError
        res.json({ success: true, data: tasks })
        break

      default:
        res.status(400).json({ error: 'Invalid action' })
    }
  } catch (error) {
    console.error('API Error:', error)
    res.status(500).json({ error: error.message })
  }
} 