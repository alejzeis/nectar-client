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
    bool startRightAway;

    package ulong lastRan;

    static Task constructRepeatingTask(TaskMethod method, ulong interval, in bool startRightAway = true) @safe nothrow {
        return Task(method, interval, true, true, startRightAway, 0);
    }

    static Task constructDelayedStartTask(TaskMethod method, ulong delay) @trusted nothrow {
        return Task(method, delay, false, true, false, getTimeMillis());
    }
}

class Scheduler {
    private Client client;
    private DList!Task tasks;

    this(Client client) @safe nothrow {
        this.client = client;
        this.tasks = DList!Task();
    }

    void registerTask(Task task, in bool important = false) @safe nothrow {
        if(important) {
            this.tasks.insertFront(task);
        } else {
            this.tasks.insertBack(task);
        }
    }

    package void doRun() @system {
        while(this.client.running) {
            if(this.tasks.empty) {
                Thread.sleep(1.msecs);
                continue;
            }

            Task task = this.tasks.front;
            if(!task.enabled) {
                this.tasks.removeFront(1);
                continue;
            }

            if(task.lastRan == 0) {
                if(task.startRightAway) {
                    task.method();
                }
                task.lastRan = getTimeMillis();
                goto finishProcess;
            }

            if((getTimeMillis() - task.lastRan) >= task.delay) {
                task.method();
                task.lastRan = getTimeMillis();
                if(!task.repeat) {
                    task.enabled = false;
                    this.tasks.removeFront(1);
                    continue;
                }
            }

finishProcess:
            this.tasks.removeFront(1);
            this.tasks.insertBack(task);

            Thread.sleep(1.msecs); // Prevent 100% CPU Usage
        }
    }
}