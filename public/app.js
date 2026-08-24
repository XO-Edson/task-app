const form = document.getElementById("task-form");
const input = document.getElementById("task-input");
const taskList = document.getElementById("task-list");

async function loadTasks() {
    try {
        const response = await fetch("/api/tasks");
        const tasks = await response.json();

        taskList.innerHTML = "";

        tasks.forEach(task => {
            addTaskToDOM(task);
        });
    } catch (error) {
        console.error("Failed to load tasks:", error);
    }
}

function addTaskToDOM(task) {
    const li = document.createElement("li");

    li.innerHTML = `
        <span>${escapeHtml(task.title)}</span>
        <button class="delete" data-id="${task.id}">
            Delete
        </button>
    `;

    taskList.appendChild(li);
}

form.addEventListener("submit", async (event) => {
    event.preventDefault();

    const title = input.value.trim();

    if (!title) {
        return;
    }

    try {
        const response = await fetch("/api/tasks", {
            method: "POST",

            headers: {
                "Content-Type": "application/json"
            },

            body: JSON.stringify({ title })
        });

        if (!response.ok) {
            throw new Error("Failed to create task");
        }

        const task = await response.json();

        addTaskToDOM(task);

        input.value = "";
    } catch (error) {
        console.error(error);
    }
});

taskList.addEventListener("click", async (event) => {
    if (!event.target.classList.contains("delete")) {
        return;
    }

    const id = event.target.dataset.id;

    try {
        const response = await fetch(`/api/tasks/${id}`, {
            method: "DELETE"
        });

        if (!response.ok) {
            throw new Error("Failed to delete task");
        }

        event.target.parentElement.remove();
    } catch (error) {
        console.error(error);
    }
});

function escapeHtml(value) {
    const div = document.createElement("div");
    div.textContent = value;
    return div.innerHTML;
}

loadTasks();