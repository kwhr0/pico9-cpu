#include "Context.h"
#include "Expr.h"
#include "Error.h"
#include "File.h"
#include "Node.h"
#include "Link.h"
#include "Prepro.h"
#include <stdint.h>
#include <unistd.h>

#define PCMSB			8
#define DATA_N			0x800
#define RET_POSTFIX		"_retadr"

static bool pass2, secData;
static int dataofs, directofs;
static std::string funcName;
static std::vector<uint32_t> text;
static std::map<std::string, int> textLabels;
static uint16_t data[DATA_N];

static std::map<std::string, int> op2 = {
	{ "mov", 010 },
	{ "and", 011 },
	{ "xor", 012 },
	{ "or",  013 },
	{ "add", 014 },
	{ "sub", 015 },
	{ "srl", 016 },
	{ "tst", 001 },
	{ "cmp", 005 },
};

static std::map<std::string, int> branch = {
	{ "b",    000 },
	{ "bz",   010 },
	{ "bnz",  011 },
	{ "bz9",  012 },
	{ "bnz9", 013 },
	{ "bc",   014 },
	{ "bnc",  015 },
	{ "bc9",  016 },
	{ "bnc9", 017 },
};

static std::map<std::string, std::pair<bool, bool>> ptr = {
	{ "lsp", { false, false } },
	{ "ldp", { false, true  } },
	{ "ssp", { true , false } },
	{ "sdp", { true , true  } },
};

static int value() {
	_ungetc(ExprContext(false, true));
	Node *t = ExprContents();
	if (!t || t->kind != Node::CONST) Error(ERR_CONST_EXPR);
	return (int)t->const_value;
}

static int target(std::string *nameptr = nullptr) {
	int v = 0;
	char c = chkch();
	if (isdigit(c)) { // local label
		std::string s = std::to_string(getint());
		auto name = funcName + s;
		if (textLabels.count(name)) v = textLabels[name];
		else if (pass2) Error(ERR_UNDEF_LABEL, s.c_str());
	}
	else { // global label
		auto s = getword();
		if (textLabels.count(s)) v = textLabels[s];
		else if (pass2) Error(ERR_UNDEF_LABEL, s.c_str());
		if (nameptr) *nameptr = s;
	}
	return v;
}

static void defineLabel(std::string name, bool isData) {
	auto &labels = isData ? G::scopeStack.back().consts : textLabels;
	if (!pass2) {
		int v = int(isData ? dataofs : text.size());
		if (isdigit(name[0])) name = funcName + name;
		if (labels.count(name)) Error(ERR_MULTI_LABEL, name.c_str());
		labels[name] = v;
		printf("%c %03x %s\n", isData ? 'D' : 'T', v, name.c_str());
	}
}

static void pushdata(int v) {
	if (!pass2) {
		if (dataofs >= DATA_N) Error(ERR_DATA_OVER);
		data[dataofs++] = v;
	}
}

static int operand(bool canImm, int size, bool rev) {
	auto &labels = G::scopeStack.back().consts;
	int r;
	char c = chkch();
	if (c == '#') {
		if (!canImm) Error(ERR_CANTIMM);
		_getc();
		int v = value();
		if (v & ~0x1ff) {
			auto s = "const_" + std::to_string(size) + "_" + std::to_string(v);
			if (labels.count(s)) r = labels[s];
			else {
				r = int(dataofs);
				defineLabel(s, true);
				for (int i = 0; i < size; i++) {
					pushdata(v & 0xff); // 8bit each
					v >>= 8;
				}
			}
		}
		else r = v | 0x800;
	}
	else {
		r = isalnum(c) || c == '-' ? value() : 0;
		if (rev) r += size - 1;
		if (r < -256 || r > 255) Error(ERR_OFFSET);
		r &= 0x1ff;
		c = chkch();
		if (c == '[') {
			_getc();
			needch(canImm ? 's' : 'd');
			needch('p');
			c = _getc();
			if (c == '-') r |= 0x600;
			else if (c == '+') r |= 0x400;
			else {
				r += 0x200;
				_ungetc(c);
			}
			needch(']');
		}
	}
	return r;
}

static int operand_ptr(bool store, bool isDst) {
	auto &labels = G::scopeStack.back().consts;
	bool imm = false;
	char c = chkch();
	if (c == '#') {
		if (store) Error(ERR_CANTIMM);
		imm = true;
		_getc();
	}
	else if (c == '\"') {
		if (store || isDst) Error(ERR_CANTIMM);
		std::string s = "";
		_getc();
		while ((c = _getc()) != '\"') s += c;
		auto name = "str_" + s;
		int ofs;
		if (labels.count(name)) ofs = labels[name];
		else {
			ofs = int(dataofs);
			defineLabel(name, true);
			for (int i = 0; i < s.length(); i++) pushdata(s[i]);
			pushdata(0);
		}
		return (ofs & 0xfff) | 0xa0000000;
	}
	return (value() & 0xfff) | (isDst ? 0x1000000 : 0) | (store ? 0x10000000 : 0) | (imm ? 0x20000000 : 0) | 0x80000000;
}

static void pseudo_data() {
	if (!pass2) {
		int ofs = getint();
		int last = (int)dataofs;
		if (last > ofs) Error(ERR_DATA_OFS, last);
		if (last < 0x200) directofs = last;
		for (int i = last; i < ofs; i++) pushdata(0);
	}
	secData = true;
}

static void pseudo_text() {
	if (directofs) dataofs = directofs;
	secData = false;
}

static void align(int ofs) {
#if PCMSB > 8
	int n = 1 << (PCMSB - 8);
	ofs += text.size() & n - 1;
	if (ofs) {
		n -= ofs;
		if (pass2 && n) printf(";align\n");
		while (n--) text.push_back(0xc0000000 | (int)text.size() + 1);
	}
#endif
}

static void pseudo_func() {
	funcName = getword();
	printf("func: %s\n", funcName.c_str());
	defineLabel(funcName, false);
	defineLabel(funcName + RET_POSTFIX, true);
	pushdata(0);
}

static void pseudo_endfunc() {
	funcName = "";
}

static void pseudo_db() {
	char c;
	do {
		pushdata(value());
		if (chkch() == ',') _getc();
		c = chkch();
	} while (isalnum(c) || c == '-');
}

using pseudo_func_t = void (*)();

static std::map<std::string, pseudo_func_t> pseudo = {
	{ "data", &pseudo_data },
	{ "text", &pseudo_text },
	{ "func", &pseudo_func },
	{ "endfunc", &pseudo_endfunc },
	{ "db", &pseudo_db },
};

static void _ParseAll(bool _pass2) {
	auto &labels = G::scopeStack.back().consts;
	pass2 = _pass2;
	text.clear();
	secData = false;
	funcName = "";
	bool comment = false;
	char c;
	while (1) {
		FileTopOfLine();
		c = _getc();
		if (!c) break;
		if (c == ';') comment = true;
		else if (c == '\n') {
			comment = false;
			continue;
		}
		if (c == '\t' || c == ' ' || comment) continue;
		std::string s;
		while (isdigit(c)) {
			s += c;
			c = _getc();
		}
		_ungetc(c);
		if (s.empty()) {
			s = getword();
			if (s.empty()) continue;
		}
		c = _getc();
		if (c == ':') {
			defineLabel(s, secData);
			s = getword();
			if (s.empty()) {
				if (pass2) FilePrintLine();
				continue;
			}
		}
		int size = 1;
		if (c == '.') size = getint();
		if (pseudo.count(s)) pseudo[s]();
		else if (secData) {
			defineLabel(s, true);
			for (int i = 0; i < size; i++) pushdata(0);
		}
		else {
			int insn = (size - 1) << 28;
			if (op2.count(s)) {
				bool rev = s == "srl";
				insn |= op2[s] << 24;
				insn |= operand(false, size, rev) << 12;
				needch(',');
				insn |= operand(true, size, rev);
			}
			else if (branch.count(s)) insn = branch[s] << 24 | (target() & 0xfff) | 0xc0000000;
			else if (ptr.count(s)) {
				auto [store, isDst] = ptr[s];
				insn = operand_ptr(store, isDst);
			}
			else if (s == "call") {
				align(1);
				std::string t;
				int a = target(&t) & 0xfff;
				t += RET_POSTFIX;
				if (labels.count(t)) insn = (labels[t] & 0xfff) << 12 | a | 0xf0000000;
				else if (pass2) Error(ERR_NO_RET_LAEBEL, s.c_str());
			}
			else if (s == "ret") {
				auto t = funcName + RET_POSTFIX;
				if (labels.count(t)) insn = (labels[t] & 0xfff) << 12 | 0xe0000000;
				else Error(ERR_NO_RET_LAEBEL, s.c_str());
			}
			else Error(ERR_UNKNOWN, s.c_str());
			if (pass2) {
				printf("%03lx %08x\t", text.size(), insn);
				FilePrintLine();
			}
			text.push_back(insn);
		}
	}
}

static void compile(const char *path, bool depend, bool preproOnly, bool pass2) {
	ErrorInit();
	ExprInit(true);
	Node::StaticInit();
	Obj::StaticInit();
	G::funcs.clear();
	//G::scopeStack.clear();
	G::dataOfs = 0;
	preprocess(path, depend, preproOnly);
	ExprInit(false);
	if (!depend) _ParseAll(pass2);
}

int main(int argc, char *argv[]) {
#if DEBUG
	printf("---- DEBUG BUILD (%d-bit) ----\n", 8 * UNIT_SIZE);
#endif
	std::string archive;
	bool preproOnly = false, compileOnly = false, depend = false;
	try {
		std::string pwd = std::string(getenv("PWD")) + '/';
		includePath.push_back(pwd);
		for (int c; (c = getopt(argc, argv, "D:EI:Ma:cl:")) != -1;) {
			bool e = false;
			std::string name, content;
			switch (c) {
				case 'D':
					for (char *p = optarg; *p; p++)
						if (*p == '=') e = true;
						else (e ? content : name) += *p;
					macrosGlobal[name] = '\0' + content;
					break;
				case 'E':
					preproOnly = true;
					break;
				case 'I':
					includePath.push_back(std::string(*optarg == '/' ? "" : pwd) + optarg + '/');
					break;
				case 'M':
					depend = true;
					break;
				case 'a':
					archive = optarg;
					break;
				case 'c':
					compileOnly = true;
					break;
				case 'l':
					ReadLibPath(optarg);
					break;
			}
		}
		std::string path = "rom.s";
		G::scopeStack.emplace_back();
		compile(path.c_str(), depend, preproOnly, false);
		if (ErrorCount()) return ErrorCount();
		if (!depend && !preproOnly) {
			compile(path.c_str(), depend, preproOnly, true);
			if (ErrorCount()) return ErrorCount();
			path = "rom.mem";
			FILE *fi = fopen(path.c_str(), "w");
			if (!fi) Fatal(FATAL_WRITE, path.c_str());
			for (int i = 0; i < text.size(); i++)
				fprintf(fi, "%08x\n", text[i]);
			fclose(fi);
			path = "ram.mem";
			fi = fopen(path.c_str(), "w");
			if (!fi) Fatal(FATAL_WRITE, path.c_str());
			for (int i = 0; i < DATA_N; i++)
				fprintf(fi, "%03x\n", data[i]);
			fclose(fi);
		}
	}
	catch (...) {}
	FileClear();
	if (!preproOnly && !compileOnly) {
		if (depend) printDepend(A_OUT, true);
//		else Link(argc, argv, archive);
	}
	return ErrorCount();
}
