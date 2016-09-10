module wdc.trackRenderer;

import camera,
	   gfm.math,
	   gfm.opengl,
	   wdc.track,
	   wdc.renderer;
import std.stdio;

class TrackRenderer : Renderer
{
	private
	{
		Track source;

		GLProgram program;
		OpenGL openGL;
		mat4f model;
		VertexSpecification!Vertex vs;

		GLVAO sectionVAO;
		GLBuffer sectionVBO;

		struct Vertex
		{
			vec3i position;
			//vec2f vertexUV;
			//vec3i inNormal;
		}
		Vertex[] sectionVertices;
	}

	this(Track sourceTrack, OpenGL openglInstance)
	{
		source = sourceTrack;
		program = createShader(openglInstance);
		openGL = openglInstance;
		model = mat4f.identity();
		vs = new VertexSpecification!Vertex(program);

		setupBuffers();
		loadSectionVertices();
		sectionVBO.setData(sectionVertices[]);
	}

	private auto createShader(OpenGL opengl)
	{
		string tunnelProgramSource =
			q{#version 330 core

			#if VERTEX_SHADER
			in ivec3 position;

			uniform mat4 mvpMatrix;
			void main()
			{
				gl_Position = mvpMatrix * vec4(position, 1.0);
			}
			#endif

			#if FRAGMENT_SHADER
			out vec3 color;

			void main()
			{
				color = vec3(1.0,1.0,0.5);
			}
			#endif
		};

		return new GLProgram(opengl, tunnelProgramSource);
	}

	void setupBuffers()
	{
		sectionVAO = new GLVAO(openGL);
		sectionVAO.bind();
		sectionVBO = new GLBuffer(openGL, GL_ARRAY_BUFFER, GL_STATIC_DRAW, sectionVertices[]);
		sectionVAO.unbind();
	}

	void loadSectionVertices()
	{
		sectionVertices.length = 0;
		
		foreach(modelInfo; source.trackSections[0].models)
		{
			foreach(polygon; modelInfo.polygons)
			{
				sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexOne].X,
				                                modelInfo.vertices[polygon.vertexIndexOne].Y,
				                                modelInfo.vertices[polygon.vertexIndexOne].Z));
				sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexTwo].X,
				                                modelInfo.vertices[polygon.vertexIndexTwo].Y,
				                                modelInfo.vertices[polygon.vertexIndexTwo].Z));
				sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexThree].X,
				                                modelInfo.vertices[polygon.vertexIndexThree].Y,
				                                modelInfo.vertices[polygon.vertexIndexThree].Z));
				if (polygon.vertexIndexFour != 0xffff)
				{
					sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexOne].X,
					                            modelInfo.vertices[polygon.vertexIndexOne].Y,
					                            modelInfo.vertices[polygon.vertexIndexOne].Z));
					sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexThree].X,
					                            modelInfo.vertices[polygon.vertexIndexThree].Y,
					                            modelInfo.vertices[polygon.vertexIndexThree].Z));
					sectionVertices ~= Vertex(vec3i(modelInfo.vertices[polygon.vertexIndexFour].X,
					                            modelInfo.vertices[polygon.vertexIndexFour].Y,
					                            modelInfo.vertices[polygon.vertexIndexFour].Z));
				}
			}
		}
	}

	void draw(Camera cam)
	{
		program.uniform("mvpMatrix").set(cam.getPVM(model));
		program.use();
		sectionVAO.bind();
		vs.use();
		glDrawArrays(GL_TRIANGLES, 0, sectionVertices.length);
		sectionVAO.unbind();
		program.unuse();
	}
}