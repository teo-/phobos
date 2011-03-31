module std.event;

/***
 * Events are an implementation of the Observer pattern.
 *
 * The observer pattern (a subset of the publish/subscribe pattern) is a software design pattern in which an object,
 * called the subject, maintains a list of its dependents, called observers, and notifies them automatically of any
 * state changes, usually by calling one of their methods. It is mainly used to implement distributed event handling
 * systems.
 * 
 * References:
 *     $(LINK2 http://en.wikipedia.org/wiki/Observer_pattern, Observer pattern)$(BR)
 * 
 * This module is based on the std.signals module, written by Walter Bright.
 */

import std.c.stdlib : realloc, free;
import core.exception : onOutOfMemoryError;
import core.sync.mutex;

/***
 * Template to define an event.
 *
 * Example:
---
import std.event;
import std.stdio;

struct EventXArgs
{
	int x;
}

class Observer1
{
	public void handler(Object sender, EventXArgs e)
	{
		writefln("Observer1: called from %s with %d", sender, e.x);
	}
}

class Observer2
{
	public void handler(int v)
	{
		writefln("Observer2: with %d", v);
	}
}

struct ObserverStruct
{
	public void handler(Object sender, EventXArgs e)
	{
		writefln("ObserverStruct: called from %s with %d", sender, e.x);
	}
}

class Subject
{
	alias void delegate(Object sender, EventXArgs e) EventXHandler;
	alias Event!(EventXHandler) EventX;
	alias void delegate(int v) EventYHandler;
	alias Event!(EventYHandler) EventY;

	public EventX XChanged;
	public EventY YChanged;

	private int _x;
	@property
	public void x(int v)
	{
		_x = v;
		EventXArgs a;
		a.x = _x;
		XChanged(this, a);
	}

	private int _y;
	@property
	public void y(int v)
	{
		_y = v;
		YChanged(_y);
	}
}

void main()
{
	auto s = new Subject();
	auto o1 = new Observer1();
	auto o2 = new Observer2();
	ObserverStruct t;

	writeln("connect..");
	s.XChanged += &o1.handler;
	s.YChanged += &o2.handler;
	s.XChanged += &t.handler;
	writeln("change..");
	s.x = 7;
	s.y = 1;
	writeln("disconnect..");
	s.XChanged -= &t.handler;
	s.YChanged -= &o2.handler;
	s.XChanged -= &o1.handler;
}
---
 * which should print:
 * <pre>
 * connect..
 * change..
 * Observer1: called from test.Subject with 7
 * ObserverStruct: called from test.Subject with 7
 * Observer2: with 1
 * disconnect..
 * </pre>
 */

struct Event(D)
{
	// the slots to call when the event is fired
	private D[] _slots;
	// used length of _slots
	private size_t _index;
	// a synchronization object
	private Mutex _lock;

	@property
	private Mutex lock()
	{
		if (_lock is null)
		{
			// lazy initialization
			_lock = new Mutex();
		}
		return _lock;
	}

	public ~this()
	{
		if (_slots)
		{
			/* **
			 * When this object is destroyed, need to let every slot
			 * know that this object is destroyed so they are not left
			 * with dangling references to it.
			 */
			version (WithDisposeEvent)
			{
				foreach (d; _slots[0 .. _index])
				{
					if (d)
					{
						Object o = _d_toObject(d.ptr);
						rt_detachDisposeEvent(o, &unhook);
					}
				}
			}
			free(_slots.ptr);
			_slots = null;
		}
	}

	/***
	 * Call each of the connected slots, passing the argument(s) to them.
	 */
	public void opCall(T ...)(T args)
	{
		synchronized (lock)
		{
			foreach (d; _slots)
			{
				if (d)
				{
					d(args);
				}
			}
		}
	}

	/***
	 * Add a slot to the list of slots to be called when the event is fired.
	 */
	private void opOpAssign(string op)(D d)
	if (op == "+")
	{
		synchronized (lock)
		{
			if (_index == _slots.length)
			{
				auto len = ((_slots.length == 0) ? 0 : _slots.length << 1) + 4;
				auto p = realloc(_slots.ptr, len * D.sizeof);
				if (!p)
				{
					onOutOfMemoryError();
				}
				_slots = (cast(D*)p)[0 .. len];
				_slots[_index .. $] = null;
			}
			_slots[_index++] = d;
			version (WithDisposeEvent)
			{
				Object o = _d_toObject(d.ptr);
				rt_attachDisposeEvent(o, &unhook);
			}
		}
	}

	/***
	 * Remove a slot from the list of slots.
	 */
	private void opOpAssign(string op)(D d)
	if (op == "-")
	{
		synchronized (lock)
		{
			for (size_t i = 0; i < _index; )
			{
				if (_slots[i] == d)
				{
					_slots[i] = _slots[--_index];
					_slots[_index] = null;
					version (WithDisposeEvent)
					{
						Object o = _d_toObject(d.ptr);
						rt_detachDisposeEvent(o, &unhook);
					}
				}
				else
				{
					i++;
				}
			}
		}
	}

	version (WithDisposeEvent)
	{
		/* **
		 * Special function called when o is destroyed.
		 * It causes any slots dependent on o to be removed from the list
		 * of slots to be called when the event is fired.
		 */
		private void unhook(Object o)
		{
			synchronized (lock)
			{
				for (size_t i = 0; i < _index; )
				{
					if (_d_toObject(_slots[i].ptr) is o)
					{
						_slots[i] = _slots[--_index];
						_slots[_index] = null;
					}
					else
					{
						i++;
					}
				}
			}
		}
	}
}

unittest
{
	struct EventXArgs
	{
		int x;
	}

	class Subject
	{
		alias void delegate(Object sender, EventXArgs e) EventXHandler;
		alias Event!(EventXHandler) EventX;
		alias void delegate(string v) EventYHandler;
		alias Event!(EventYHandler) EventY;

		private int _x;
		private string _y;
		public EventX XChanged;
		public EventY YChanged;

		@property
		public void x(int v)
		{
			_x = v;
			EventXArgs a;
			a.x = _x;
			XChanged(this, a);
		}

		@property
		public void y(string v)
		{
			_y = v;
			YChanged(_y);
		}
	}

	class Observer
	{
		public Object _o;
		public int _x;
		public string _m;

		public void handlerX(Object o, EventXArgs a)
		{
			_o = o;
			_x = a.x;
		}

		public void handlerY(string s)
		{
			_m = s;
		}

		public void reset()
		{
			_o = Object.init;
			_x = int.init;
			_m = string.init;
		}
	}

	auto s = new Subject();
	auto o = new Observer();

	// check initial condition
	assert(o._o is null);
	assert(o._x == 0);
	assert(o._m == "");
	o.reset();

	// set a value while no observation is in place
	s.x = 1;
	s.y = "one";
	assert(o._o is null);
	assert(o._x == 0);
	assert(o._m == "");
	o.reset();

	// connect the observer and trigger it
	s.XChanged += &o.handlerX;
	s.YChanged += &o.handlerY;
	s.x = 2;
	s.y = "two";
	assert(o._o is s);
	assert(o._x == 2);
	assert(o._m == "two");
	o.reset();

	// disconnect the observer and make sure it doesn't trigger
	s.XChanged -= &o.handlerX;
	s.YChanged -= &o.handlerY;
	s.x = 3;
	s.y = "three";
	assert(o._o is null);
	assert(o._x == 0);
	assert(o._m == "");
	o.reset();

	// reconnect the watcher and make sure it triggers
	s.XChanged += &o.handlerX;
	s.YChanged += &o.handlerY;
	s.x = 4;
	s.y = "four";
	assert(o._o is s);
	assert(o._x == 4);
	assert(o._m == "four");
	o.reset();

	// delete the underlying object and make sure it doesn't cause a crash or other problems
	/*
	delete o;
	s.x = 5;
	s.y = "five";
	*/
}

private
{
	// Special function for internal use only.
	// Use of this is where the slot had better be a delegate
	// to an object or an interface that is part of an object.
	extern(C) Object _d_toObject(void* p);
	// Used in place of Object.notifyRegister and Object.notifyUnRegister.
	alias void delegate(Object) DisposeEvent;
	extern(C) void rt_attachDisposeEvent(Object o, DisposeEvent e);
	extern(C) void rt_detachDisposeEvent(Object o, DisposeEvent e);
}
