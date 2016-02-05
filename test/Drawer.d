
module test.drawer;

import gfm.math,
	   gfm.opengl,
	   camera;

class Drawer {
	private struct Vertex
	{
		vec3f position;
	}
	private Vertex[3] triangle;
	private mat4f model;
	private GLProgram program;
	private GLVAO vao;
	private GLBuffer vbo;
	private VertexSpecification!Vertex vs;

	this(OpenGL opengl, GLProgram prgrm)
	{
		this.program = prgrm;

		model = mat4f.translation(vec3f(0, 0, 0));

		triangle[0] = Vertex(vec3f(-0.1, -0.1, 0));
		triangle[1] = Vertex(vec3f(+0.1, -0.1, 0));
		triangle[2] = Vertex(vec3f(+0.1, +0.1, 0));

		this.vao = new GLVAO(opengl);

		vbo = new GLBuffer(opengl, GL_ARRAY_BUFFER, GL_STATIC_DRAW, triangle[]);

		vs = new VertexSpecification!Vertex(program);

		vao.bind();
		vbo.bind();
		vs.use();
		vao.unbind();
	}

	public void drawTriangles(Camera cam)
	{
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		vao.bind();
		glDrawArrays(GL_TRIANGLES, 0, cast(int)(vbo.size() / vs.vertexSize()));
		vao.unbind();
		program.unuse();
	}

	public void drawPoints()
	{
		program.uniform("mvpMatrix").set(mat4f.identity);
		program.use();
		vao.bind();
		glDrawArrays(GL_POINTS, 0, cast(int)(vbo.size() / vs.vertexSize()));
		vao.unbind();
		program.unuse();
	}
}