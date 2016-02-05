
import std.algorithm,
		core.time: MonoTime;

class TimeKeeper
{
static:
	private
	{
		 MonoTime previousTime;
		 float deltaTime;
		 int targetFPS;
	}

	public void start(int fps) {
		previousTime = MonoTime.currTime();
		targetFPS = fps;
	}

	public void startNewFrame() {
		MonoTime now = MonoTime.currTime();
		deltaTime = (now - previousTime).total!"usecs" / 1_000_000f;
		previousTime = now;
	}

	public float getDeltaTime() {
		return deltaTime;
	}

	public long uSecsUntilNextFrame() {
		return max(0, (1_000_000L / targetFPS) - (MonoTime.currTime() - previousTime).total!"usecs");
	}
}