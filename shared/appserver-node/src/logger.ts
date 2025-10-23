/**
 * Structured JSON logger for correlation tracking
 */

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

interface LogEntry {
  level?: LogLevel;
  timestamp?: string;
  [key: string]: any;
}

class Logger {
  private minLevel: LogLevel;

  constructor() {
    const envLevel = process.env.LOG_LEVEL?.toLowerCase() as LogLevel;
    this.minLevel = envLevel || 'info';
  }

  private shouldLog(level: LogLevel): boolean {
    const levels: LogLevel[] = ['debug', 'info', 'warn', 'error'];
    const minIndex = levels.indexOf(this.minLevel);
    const currentIndex = levels.indexOf(level);
    return currentIndex >= minIndex;
  }

  private log(level: LogLevel, entry: LogEntry): void {
    if (!this.shouldLog(level)) return;

    const logEntry: LogEntry = {
      level,
      timestamp: new Date().toISOString(),
      ...entry
    };

    const output = JSON.stringify(logEntry);
    
    if (level === 'error') {
      console.error(output);
    } else {
      console.log(output);
    }
  }

  debug(entry: LogEntry): void {
    this.log('debug', entry);
  }

  info(entry: LogEntry): void {
    this.log('info', entry);
  }

  warn(entry: LogEntry): void {
    this.log('warn', entry);
  }

  error(entry: LogEntry): void {
    this.log('error', entry);
  }
}

export const logger = new Logger();
