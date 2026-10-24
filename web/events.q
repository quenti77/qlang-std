--" # Events

Parts of an application that should not know each other talk through events: one side says
"this happened", the others listen. An event is any value, usually a small struct.

```
struct UserRegistered
  public id: int
  public email: string
end

let events = Events.new()
events.listen<UserRegistered>(fun(e: UserRegistered) send_welcome(e.email) end)
events.listen<UserRegistered>(fun(e: UserRegistered) Log.info("new user {e.id}") end)

events.dispatch(UserRegistered { id: 1, email: "ada@example.org" })
```

Listeners are called in the order they were added, one after the other, in the request that
dispatched the event (there is no background queue). A listener that fails does not stop the
others: its error is logged and `dispatch` goes on. Listeners belong to the worker that added them:
add them when the application starts.
--"

--" A set of listeners, by the type of event. --"
struct Events
  listeners: map<string, array<fun(Any)>>
end

impl Events
  public fun new() -> Events
    Events { listeners: {} }
  end

  --" Calls `handler` for every event of type `E` dispatched from now on. --"
  public fun listen<E>(self, handler: fun(E))
    let key = Reflect.type_name<E>()
    let wrapped = fun(event: Any)
      let typed = event.as<E>()
      if typed != none then
        handler(typed)
      end
    end
    let found = self.listeners[key]
    if found == none then
      self.listeners[key] = [wrapped]
    else
      found.push(wrapped)
    end
  end

  --" Tells the listeners of the type of `event`. Gives back how many were called. --"
  public fun dispatch<E>(self, event: E) -> int
    let found = self.listeners[Reflect.type_name<E>()]
    if found == none then
      return 0
    end
    let boxed = Any.of(event)
    for listener in found do
      listener(boxed)
    end
    found.len()
  end

  --" How many listeners wait for events of type `E`. --"
  public fun count<E>(self) -> int
    let found = self.listeners[Reflect.type_name<E>()]
    if found == none then 0 else found.len() end
  end
end

export Events
