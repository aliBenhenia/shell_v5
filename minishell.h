#ifndef MINISHELL_H
#define MINISHELL_H

#include <unistd.h>
#include <sys/wait.h>
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <string.h>
#include <fcntl.h>
#include <readline/readline.h>
# include <readline/history.h>


#define SPACE 0
#define APPEND 1
#define HEREDOC 2
#define RIGHTRED 3
#define LEFTRED 4
#define DOLLAR 5
#define PIPE 6
#define S_QUOTE 7
#define D_QUOTE 8
#define WORD 9
#define AFDOLLAR 10
#define NLINE 11

typedef struct line
{
    char        *value;
    int         type;
    struct line *next;
    struct line *prev;
}t_token_list;

typedef struct redirections
{
    int					type;
    char				*file;
    int fd;
	struct redirections *next;
}t_redirections;

typedef enum sep
{
    e_nline,
    e_pipe,
} t_sep;
///
typedef struct cmd_line
{
    char            **str;
    t_redirections  *redirections;
    t_sep			separator;
    struct cmd_line *next;
}t_cmd_line;
///
typedef	struct env_list
{
	char			*name;
	char			*value;
	struct env_list	*next;
}t_env_list;
typedef struct  t_export
{
    char *var;
    char *value;
    struct t_export *next;
    
}t_export;

typedef struct tools
{
    int there_is_dollar;
    int s_quote;
    int d_quote;
    int no_expand;
    int dollar_in;
}t_tools;

typedef struct exec_tools
{
    t_cmd_line		*cmd_tmp;
    int 			no_file;
    t_redirections	*l_infile;
    t_redirections	*l_outfile;
    int 			i;
    int 			flg;
    pid_t			pid;
    int				heredoc_fd;
}t_exec_tools;

// Tokenizer Utils
t_token_list    *tokenizer(char *line, t_tools *tools);
char			*is_redirections(t_token_list **tokens, char *line, t_tools *tools);
char			*is_wspace(t_token_list **tokens, char *line);
char			*is_dollar_pipe(t_token_list **tokens, char *line);
char			*is_word(t_token_list **tokens, char *line);
char			*is_squote(t_token_list **tokens, char *line, t_tools *tools);
char			*is_dquote(t_token_list **tokens, char *line, t_tools *tools);
char			*afdollar(t_token_list **tokens, char *line);
char			*is_space(t_token_list **tokens, char *line);
char			*ft_dquotes(t_token_list **tokens, char *line, t_tools *tools);
char            *no_expand(t_token_list **tokens, char	*line, t_tools *tools);
void	open_quote_error(t_token_list **tokens);


// Expander
void	        expand(t_token_list **tokens, t_env_list **env);
t_env_list	    *add_var(char *name, char *value);
void	        fill_env_list(t_env_list **env_list, t_env_list *new);
void	        env_vars_list(t_env_list **env_list, char **env);

// Syntax
int	            syntax(t_token_list *tokens);

// Parser
void			*parser(t_cmd_line **cmd_line, t_token_list *tokens);
t_redirections	*init_redirection(int type, char *file);
void			fill_redirections_list(t_redirections **redirections, t_redirections *new);
void			separator(t_cmd_line *cmd, t_token_list *token);
t_cmd_line		*init_cmdline(char **str, t_redirections *redirections, t_token_list *token);
void			fill_cmd_line(t_cmd_line **cmdline, t_cmd_line *new);
int				to_alloc_count(t_token_list **tokens);

// Execution
void execution(t_cmd_line **cmd_line, t_env_list **env_list,t_export **export_list);
int     main_builtins(t_cmd_line **cmd_line);
void    execute_builtins(t_cmd_line **cmd_line, t_env_list **env_list,t_export **export_list);
int	    builtins(char	*cmd);
void	exec_builtins(char	**str, t_env_list **env_list, int code, t_export **export);

char    *get_home_var(t_env_list **env_list);
char	**get_path(t_env_list **env_list);
int     count_list(t_cmd_line **cmd_line);
int     count_envlist(t_env_list **env_list);
char    **create_envp(t_env_list **env_list);


void			ft_cd(char *path, t_env_list **env_list);
void    		ft_pwd(void);
t_redirections  *last_outfile(t_cmd_line **cmd_line);
t_redirections  *last_infile(t_cmd_line **cmd_line, int *no_file);
void 			dup_to_pipe(int **fd, int i, int cmds);
void			dup_outfile(t_redirections *redirection);
void			dup_infile(t_redirections *redirection);
void			close_pipes(int **fd, int i, int cmds, int flag);
void    		ft_heredoc(t_cmd_line **cmd_line, int *fd);
void			execute_command_2(t_cmd_line **cmd_line, t_env_list **env_list,t_export **export);
void			execve_func(char **cmd, t_env_list **env_list);
char            *check_command_in_path(char **path, char *cmd);

void    ft_echo(char **str);

void	ft_putstr(char	*str);
void	free_2d(char **str);
int	ft_isalnum(int c);
int is_open_quote(char *line, char quote);
int     ft_strcmp(char *s1, char *s2);
int	ft_strncmp(const char *str1, const char *str2, size_t n);
int     ft_strlen(char *str);
int		count(char *line);
int		inside_quotes(char *line, int i);
int     all_spaces(char *line, int i);
char    *skip_wspaces(char *line);
char    *remove_additional_spaces(char *line);
char	*ft_strchr(char *str, int c);
void	ft_lstclear(t_token_list	**lst);
void    addback(t_token_list **tokens, char *value, int type);
char	*ft_strjoin(char *s1, char *s2);
char	**ft_split(char const *s, char c);
t_token_list *new_token(char *value, int type);
char	*ft_itoa(int n);
char	*ft_strdup(char *src);
char	*ft_strndup(char *src, int len);


#endif