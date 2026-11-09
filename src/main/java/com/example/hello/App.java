package com.example.hello;

/** Entry point: prints a greeting. */
public final class App {

    private App() {
    }

    public static void main(String[] args) {
        System.out.println(greeting(args));
    }

    /** Greets the first argument if present and not blank, otherwise the world. */
    static String greeting(String[] args) {
        if (args.length > 0 && !args[0].isBlank()) {
            return Greeter.greet(args[0]);
        }
        return Greeter.greet("world");
    }
}
