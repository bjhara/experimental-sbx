package com.example.hello;

/** Entry point: prints a greeting. */
public final class App {

    private App() {
    }

    public static void main(String[] args) {
        System.out.println(Greeter.greet("world"));
    }
}
