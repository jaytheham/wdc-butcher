
module test.drawer;

import gfm.math,
	   gfm.opengl,
	   camera;

class Drawer {
	private struct Vertex
	{
		vec3i position;
	}
	private Vertex[] triangle;
	private ushort[] indices;
	private mat4f model;
	private GLProgram program;
	private GLVAO vao;
	private GLBuffer vbo;
	private GLBuffer vibo;
	private VertexSpecification!Vertex vs;

	this(OpenGL opengl, GLProgram prgrm)
	{
		this.program = prgrm;

		model = mat4f.translation(vec3f(0, 0, 0));

		indices = [0,1,5];

		triangle ~= Vertex(vec3i(0, 0, 0));
		triangle ~= Vertex(vec3i(0, 100, 0));
		triangle ~= Vertex(vec3i(0, 0, 0));
		triangle ~= Vertex(vec3i(100, 0, 0));
		triangle ~= Vertex(vec3i(0, 0, 0));
		triangle ~= Vertex(vec3i(0, 0, 100));

		this.vao = new GLVAO(opengl);

		vbo = new GLBuffer(opengl, GL_ARRAY_BUFFER, GL_STATIC_DRAW, triangle[]);
		vibo = new GLBuffer(opengl, GL_ELEMENT_ARRAY_BUFFER, GL_STATIC_DRAW, indices[]);

		vs = new VertexSpecification!Vertex(program);

		vao.bind();
		vibo.bind();
		vbo.bind();
		vs.use();
		vao.unbind();
	}

	public void drawTriangles(Camera cam)
	{
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		vao.bind();
		//glDrawArrays(GL_TRIANGLES, 0, cast(int)(vbo.size() / vs.vertexSize()));
		glDrawElements(GL_TRIANGLES, indices.length, GL_UNSIGNED_SHORT, cast(void*)0);
		vao.unbind();
		program.unuse();
	}

	public void drawOrigin(Camera cam)
	{
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		vao.bind();
		glDrawArrays(GL_LINES, 0, cast(int)(vbo.size() / vs.vertexSize()));
		vao.unbind();
		program.unuse();
	}
}