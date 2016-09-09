module wdc.drawable;

import camera,
	   gfm.opengl,
	   wdc.renderer;

interface Drawable
{
	// move these two onto renderer, drawable just means it has a renderer, which does the actual drawing
	void enableDrawing(OpenGL openglInstance, GLProgram programInstance);
	void draw(Camera cam);

	Renderer getRenderer(OpenGL openglInstance, GLProgram programInstance);
}