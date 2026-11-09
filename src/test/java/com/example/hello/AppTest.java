package com.example.hello;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class AppTest {

    @Test
    void greetsTheWorldWithoutArguments() {
        assertEquals("Hello, world!", App.greeting(new String[] {}));
    }

    @Test
    void greetsTheGivenName() {
        assertEquals("Hello, Alice!", App.greeting(new String[] {"Alice"}));
    }

    @Test
    void usesOnlyTheFirstArgument() {
        assertEquals("Hello, Alice!", App.greeting(new String[] {"Alice", "Bob"}));
    }

    @Test
    void treatsEmptyArgumentAsNoName() {
        assertEquals("Hello, world!", App.greeting(new String[] {""}));
    }

    @Test
    void treatsBlankArgumentAsNoName() {
        assertEquals("Hello, world!", App.greeting(new String[] {"  "}));
    }
}
