const express = require("express");
const path = require("path");
const { Pool } = require("pg");
require("dotenv").config();

const app = express();

const PORT = process.env.PORT || 3000;

const pool = new Pool({
  host: process.env.DATABASE_HOST,
  port: process.env.DATABASE_PORT,
  database: process.env.DATABASE_NAME,
  user: process.env.DATABASE_USER,
  password: process.env.DATABASE_PASSWORD
});

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// Health check
app.get("/health", async (req, res) => {
  try {
    await pool.query("SELECT 1");

    res.json({
      status: "ok",
      database: "connected"
    });
  } catch (error) {
    res.status(500).json({
      status: "error",
      database: "disconnected"
    });
  }
});

// Get all tasks
app.get("/api/tasks", async (req, res) => {
  try {
    const result = await pool.query(
      "SELECT * FROM tasks ORDER BY id DESC"
    );

    res.json(result.rows);
  } catch (error) {
    console.error(error);
    res.status(500).json({
      error: "Failed to fetch tasks"
    });
  }
});

// Create a task
app.post("/api/tasks", async (req, res) => {
  const { title } = req.body;

  if (!title || title.trim() === "") {
    return res.status(400).json({
      error: "Task title is required"
    });
  }

  try {
    const result = await pool.query(
      "INSERT INTO tasks (title) VALUES ($1) RETURNING *",
      [title.trim()]
    );

    res.status(201).json(result.rows[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({
      error: "Failed to create task"
    });
  }
});

// Delete a task
app.delete("/api/tasks/:id", async (req, res) => {
  const { id } = req.params;

  try {
    const result = await pool.query(
      "DELETE FROM tasks WHERE id = $1 RETURNING *",
      [id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: "Task not found"
      });
    }

    res.json(result.rows[0]);
  } catch (error) {
    console.error(error);
    res.status(500).json({
      error: "Failed to delete task"
    });
  }
});

app.listen(PORT, () => {
  console.log(`Task app running on port ${PORT}`);
});