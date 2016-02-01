
import gfm.math,
	gfm.opengl;

class testDrawer {
	private struct Vertex
    {
        vec3f position;
    }
	private Vertex[3] triangle;
	private OpenGL gl;
	private GLProgram program;
	private GLVAO vao;
	private GLBuffer vbo;
	private VertexSpecification!Vertex vs;

	this(OpenGL opengl, GLProgram prgrm) {
		this.gl = opengl;
		this.program = prgrm;
    	triangle[0] = Vertex(vec3f(-1, -1, 0));
    	triangle[1] = Vertex(vec3f(+1, -1, 0));
    	triangle[2] = Vertex(vec3f(+1, +1, 0));

    	this.vao = new GLVAO(this.gl);

    	vbo = new GLBuffer(this.gl, GL_ARRAY_BUFFER, GL_STATIC_DRAW, triangle[]);

    	vs = new VertexSpecification!Vertex(this.program);

    	this.vao.bind();
        vbo.bind();
        vs.use();
        this.vao.unbind();
	}

	public void draw() {
		this.program.use();
		vao.bind();
        glDrawArrays(GL_TRIANGLES, 0, cast(int)(vbo.size() / vs.vertexSize()));
        vao.unbind();
		this.program.unuse();
	}
}