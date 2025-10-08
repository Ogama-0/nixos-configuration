CFLAGS = -Wall -Wextra -Wno-unused-parameter -lSDL2
CC = clang
SRC = device.c
OBJ = $(SRC:.c=.o)
EXEC = device

all: $(EXEC)

$(EXEC): $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^
	@echo runing the application
	@./device
	@echo exiting the application
	@make clean

clean:
	rm -f $(OBJ) $(EXEC)
	# rm -f output.bmp

