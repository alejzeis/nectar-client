module nectar_client.logging;

import std.conv : to;
import std.datetime;
import std.experimental.logger;
import std.file : exists, append, remove;

class NectarLogger : Logger {
    private immutable bool writeStdout;
    private immutable string logFileLocation;

    this(LogLevel level, in string logFileLocation = null, in bool writeStdout = true) @trusted {
        import consoled : title;
        super(level);

        if(writeStdout) title = "Nectar-Client";

        this.logFileLocation = logFileLocation;
        this.writeStdout = writeStdout;

        if(!(this.logFileLocation is null)) {
            if(exists(this.logFileLocation)) {
                remove(this.logFileLocation);
            }
        }
    }

    override void writeLogMsg(ref LogEntry payload) @trusted {
        import std.stdio : write;
        import consoled : foreground, Fg, FontStyle, writec;

        string msg = getTimeString() ~ " [" ~ levelToStr(payload.logLevel) ~ "/" ~ to!string(payload.threadId) ~ "]: " ~ payload.msg;
        
        if(writeStdout) {

            auto old = foreground;
            
            writec(Fg.white, getTimeString(), " [");

            levelToStr(payload.logLevel, true);

            writec(FontStyle.none, Fg.white, "/", Fg.lightBlue, payload.threadId, Fg.white, "]: ");

            foreground = old;

            write(payload.msg ~ "\n");
        }

        if(!(this.logFileLocation is null)) {
            append(this.logFileLocation, msg ~ "\n");
        }
    }

    private string getTimeString() @safe {
        auto time = Clock.currTime();
        return "[" ~ to!string(time.year) ~ "-" ~ to!string(time.day) ~ "-" 
        ~ to!string(time.month) ~ " " ~ to!string(time.hour) ~ ":" ~ to!string(time.minute) ~ ":" ~ to!string(time.second) ~ "]";
    }

    private string levelToStr(LogLevel level, bool print = false) {
        import std.stdio : write;
        import consoled : writec, Fg, FontStyle;

        switch(level) {
            case LogLevel.info:
                if(print)
                    writec(FontStyle.bold, Fg.lightGreen, "INFO");
                return "INFO";
            case LogLevel.critical:
                if(print)
                    writec(FontStyle.bold, Fg.red, "CRITICAL");
                return "CRITICAL";
            case LogLevel.warning:
                if(print)
                    writec(FontStyle.bold, Fg.yellow, "WARNING");
                return "WARNING";
            case LogLevel.error:
                if(print)
                    writec(FontStyle.bold, Fg.red, "ERROR");
                return "ERROR";
            case LogLevel.trace:
                if(print)
                    writec(FontStyle.bold, Fg.cyan, "TRACE");
                return "TRACE";
            case LogLevel.fatal:
                if(print)
                    writec(FontStyle.bold, Fg.lightRed, "FATAL");
                return "FATAL";
            default:
                return "UNKNOWN";
        }
    }
}