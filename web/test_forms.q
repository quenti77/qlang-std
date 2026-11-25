-- A form with a group of checkboxes, for the tests of `app.q`.
import Post, Body from "app.q"

struct Picks
    public name: string
    public tags: array<string>
    public sizes: array<int>
end

#[Post("/picks")]
fun picks(#[Body] input: Picks) -> string
    "{input.name}:{input.tags.join(",")}:{input.sizes.len()}"
end
