module wdc.renderer;

import camera;

interface Renderer
{
	void draw(Camera cam);

	// drawWholeObject ? i.e. all car parts / all track parts at once
}