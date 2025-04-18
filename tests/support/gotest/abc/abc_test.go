package abc_test

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"testing"
	"time"

	"gotest/abc"
)

func TestSum(t *testing.T) {
	// run current test with <leader>tr
	// run current file with <leader>tR
	// you can also keep opened both split and popup
	a := 1
	b := 2
	c := abc.Sum(a, b)

	fmt.Println("hi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!")
	time.Sleep(time.Millisecond * 500)
	fmt.Println("hi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!")
	time.Sleep(time.Millisecond * 500)
	fmt.Println("hi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!")
	time.Sleep(time.Millisecond * 500)
	fmt.Println("hi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!\nhi!")

	if c != a+b+1 {
		t.Errorf("Sum(%d, %d) = %d, want %d", a, b, c, a+b)
	}
}

func TestIndent(t *testing.T) {
	fmt.Printf("not indented\n")
	fmt.Printf("\tindented\n")
	fmt.Printf("\t\tindented twice\n")
}

func TestGradient(t *testing.T) {
	width := 80
	height := 24

	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			r := uint8(255 * float64(x) / float64(width-1))
			g := uint8(255 * float64(y) / float64(height-1))
			b := uint8(255 * math.Abs(math.Sin(float64(x*y)/100)))

			fmt.Printf("\x1b[48;2;%d;%d;%dm ", r, g, b)
		}
		fmt.Print("\x1b[0m\n")
	}
}

func TestSum2(t *testing.T) {
	fmt.Println("TestSum2 hey!")

	fmt.Fprint(os.Stderr, "number of foo\n")

	t.Run("TestSum", func(t *testing.T) {
		a := 1
		b := 2
		c := abc.Sum(a, b)
		if c != a+b {
			t.Errorf("Sum(%d, %d) = %d, want %d", a, b, c, a+b)
		} else {
			t.Log("TestSum passed")
		}
	})
}

func TestIntensiveOutput(t *testing.T) {
	for i := range 10000 {
		fmt.Println("hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!hi!" + strconv.Itoa(i))
	}
}
