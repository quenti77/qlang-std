import "app.q" as tasks
import "../../web/testing.q" as testing
import Task from "providers.q"
import Credentials, NewTask from "controllers.q"

const ADA = Credentials { email: "ada@example.org", password: "correct horse" }

fun signed_in() -> testing.Client
  let client = testing.Client.new(tasks.build())
  client.post_json("/register", ADA).expect_status(201)
  client.post_json("/login", ADA).expect_status(200)
  client
end

fun test_the_application_is_wired()
  assert_eq(tasks.build().validate(), [])
end

fun test_public_routes_need_no_login_and_private_ones_do()
  let client = testing.Client.new(tasks.build())
  client.get("/health").expect_status(200)
  client.get("/tasks").expect_status(401)
  client.get("/me").expect_status(401)
end

fun test_registering_hashes_the_password_and_refuses_a_second_time()
  let client = testing.Client.new(tasks.build())
  let made = client.post_json("/register", ADA).expect_status(201)
  assert(not made.body.contains("password"))
  client.post_json("/register", ADA).expect_status(409)
  client.post_json("/register", Credentials { email: "nope", password: "short" }).expect_status(422)
end

fun test_logging_in_opens_a_session_and_a_wrong_password_does_not()
  let client = testing.Client.new(tasks.build())
  client.post_json("/register", ADA)
  client.post_json("/login", Credentials { email: "ada@example.org", password: "wrong password" }).expect_status(401)
  client.get("/me").expect_status(401)
  client.post_json("/login", ADA).expect_status(200)
  assert(client.get("/me").expect_status(200).body.contains("ada@example.org"))
  client.post("/logout", "").expect_status(204)
  client.get("/me").expect_status(401)
end

fun test_a_user_creates_lists_finishes_and_deletes_tasks()
  let client = signed_in()
  let made = client.post_json("/tasks", NewTask { title: "Write the guide" }).expect_status(201)
  let task = made.json<Task>().unwrap()
  assert_eq(task.title, "Write the guide")
  assert_eq(client.get("/tasks").json<array<Task>>().unwrap().len(), 1)
  client.post("/tasks/{task.id}/done", "").expect_status(200)
  assert_eq(client.get("/tasks?done=true").json<array<Task>>().unwrap().len(), 1)
  assert_eq(client.get("/tasks?done=false").json<array<Task>>().unwrap().len(), 0)
  client.delete("/tasks/{task.id}").expect_status(204)
  client.get("/tasks/{task.id}").expect_status(404)
  client.delete("/tasks/{task.id}").expect_status(404)
end

fun test_a_bad_task_is_refused_with_the_details()
  let client = signed_in()
  let refused = client.post_json("/tasks", NewTask { title: "" }).expect_status(422)
  assert(refused.body.contains("title"))
end

fun test_a_form_works_like_json()
  let client = signed_in()
  client.post_form("/tasks", {"title": "From a form"}).expect_status(201)
  client.post_form("/tasks", {"title": ""}).expect_status(422)
end
