module nectar_client.scheduler;

import std.container;
import std.datetime;
import std.conv;

import core.thread;

import nectar_client.util;
import nectar_client.client;

alias TaskMethod = void delegate();

struct Task {
    TaskMethod method;
    ulong delay;
    bool repeat;
    bool enabled;

    package ulong lastRan;

    static Task constructRepeatingTask(TaskMethod method, ulong interval) {
        return Task(method, interval, true, true, 0);
    }

    static Task constructDelayedStartTask(TaskMethod method, ulong delay) {
        return Task(method, delay, false, true, getTimeMillis());
    }
}

class Scheduler {
    private Client client;
    private DList!Task tasks;

    this(Client client) {
        this.client = client;
        this.tasks = DList!Task();
    }

    void registerTask(Task task) {
        this.tasks.insertBack(task);
    }

    package void doRun() {
        while(this.client.running) {
            if(this.tasks.empty) {
                Thread.sleep(50.msecs);
                continue;
            }

            Task task = this.tasks.front;
            if(!task.enabled) {
                this.tasks.removeFront(1);
                continue;
            }

            if(task.lastRan == 0) {
                task.method();
                task.lastRan = getTimeMillis();
                goto finishProcess;
            }

            if((getTimeMillis() - task.lastRan) >= task.delay) {
                task.method();
                task.lastRan = getTimeMillis();
                if(!task.repeat) task.enabled = false;
            }

finishProcess:
            this.tasks.removeFront(1);
            this.tasks.insertBack(task);

            Thread.sleep(1.msecs); // Prevent 100% CPU Usage
        }
    }
}