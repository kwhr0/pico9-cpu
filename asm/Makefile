OBJS = main.o Context.o Error.o Expr.o File.o Link.o Node.o Obj.o Prepro.o
CXXFLAGS = -std=c++17

all: asm

asm: $(OBJS)
	c++ $(OBJS) -o $@

clean:
	rm -f *.o asm
