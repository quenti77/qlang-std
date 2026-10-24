-- The commands of the blog: functions whose parameters say where their values come from.
import "../../cli.q" as cli
import Posts from "providers.q"

#[cli.Command("posts:list", "Lists the posts")]
fun posts_list(posts: Posts, console: cli.Console, #[cli.Opt(short: "n", description: "how many")] limit: int?)
  let rows: array<array<string>> = []
  for p in posts.all(limit ?? 20) do
    rows.push(["{p.id}", p.title, p.author])
  end
  console.table(["id", "title", "author"], rows)
end

#[cli.Command("posts:add", "Adds a post")]
fun posts_add(#[cli.Arg(description: "the title")] title: string, #[cli.Opt(description: "the author")] author: string?, posts: Posts, console: cli.Console)
  let made = posts.add(title, "(written from the command line)", author ?? "console")
  console.line("Added post {made.id}")
end
