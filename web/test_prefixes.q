-- Controllers with the three ways of writing "no prefix" and a prefix with a trailing slash.
import Controller, Get from "app.q"

#[Controller("")]
struct NoPrefix
end

impl NoPrefix
    #[Get("/login")]
    public fun login(self) -> string
        "empty"
    end
end

#[Controller("/")]
struct SlashPrefix
end

impl SlashPrefix
    #[Get("/signin")]
    public fun signin(self) -> string
        "slash"
    end

    #[Get("/")]
    public fun home(self) -> string
        "home"
    end
end

#[Controller("/x/")]
struct TrailingPrefix
end

impl TrailingPrefix
    #[Get("/y")]
    public fun y(self) -> string
        "trailing"
    end
end
