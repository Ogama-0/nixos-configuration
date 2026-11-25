# Greeter tests

The greeter is the one surface in this repo that nothing else can exercise.
It is instantiated exactly once per boot, by a compositor started by greetd,
as a user with no home directory — so a QML load error in it is invisible to
`nix flake check`, to every fixture in `tests/laserbar/`, and to any amount of
reading. It shows up at the login screen, which is the worst possible place to
find out.

`scripts/greeter-check.sh` is the substitute. It does two things:

1. **Loads both built surfaces** in a nested headless sway and fails on any
   QML warning. This catches the class of bug that has actually happened here:
   a property dropped during an edit (`session.outbox` went missing and every
   login would have thrown `TypeError: Cannot read property 'length' of
   undefined`), two handlers on one signal, a bad import.

2. **Drives `GreetdSession` against a fake greetd** that speaks the real
   length-prefixed protocol, through both howdy outcomes:

   - face accepted — `sufficient` means pam_unix never runs, so the greeter
     must reach `authenticated` having sent only an empty answer to the info
     message, and must never ask for a password;
   - face rejected — info → error → secret, every one of which needs an
     answer, with the password handed over only at the last.

   Both of those were broken: the handler answered `secret` and nothing else,
   so greetd waited forever for a reply to the `info` and the greeter hung.

Run it against the working tree:

```sh
scripts/greeter-check.sh
```

It builds the system closure to get the rendered QML — the `@token@`
substitution in `modules/features/desktop/greeter.nix` is what turns these
files into valid QML, so testing the sources directly is meaningless.
