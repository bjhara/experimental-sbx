package com.example.hello;

/** Builds greetings. */
public final class Greeter {

    private Greeter() {
    }

    /** Returns a greeting for {@code name}, e.g. "Hello, world!". */
    public static String greet(String name) {
        return "Hello, " + name + "!";
    }
}
