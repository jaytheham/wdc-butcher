module wdc.drawable;

import camera,
	   gfm.opengl,
	   wdc.renderer;

interface Drawable
{
	void setupDrawing(OpenGL openglInstance);

	// is just a passthrough to the renderer
	void draw(Camera cam, char[] args);
}