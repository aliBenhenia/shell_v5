/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   tokenizer_utils2.c                                 :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: mazaroua <mazaroua@student.42.fr>          +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2023/04/03 16:40:48 by mazaroua          #+#    #+#             */
/*   Updated: 2023/04/05 15:01:57 by mazaroua         ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "minishell.h"

int count_var_len(char *line)
{
    int i;

    i = 0;
    while (line[i])
    {
        if ((line[i] != 34) && (ft_isalnum(line[i]) || line[i] == '_'))
			i++;
		else
			break;
    }
    return (i);
}

char    *is_redirections(t_token_list **tokens, char *line, t_tools *tools)
{
    if (!line)
        return (NULL);
    if (*line == '>')
    {	
        if (*(line + 1) == '>')
        {
            addback(tokens, ">>", APPEND);
            return (line + 2);
        }
        addback(tokens, ">", RIGHTRED);
    }
    else if (*line == '<')
    {
        if (*(line + 1) == '<')
        {
            addback(tokens, "<<", HEREDOC);
            line = is_wspace(tokens, line + 2);
            while (*line == 34)
            {
                tools->no_expand = 0;
                line = no_expand(tokens, line, tools);
                if (tools->no_expand == 1)
                {
                    open_quote_error(tokens);
                    return (NULL);
                }
            }
            if (*line == '$')
            {
                addback(tokens, ft_strndup(line, count_var_len(line + 1) + 1), WORD);
                line = line + count_var_len(line + 1) + 1;
            }
            return (line);
        }
        addback(tokens, "<", LEFTRED);
    }
	return (line + 1);
}

char    *is_wspace(t_token_list **tokens, char *line)
{
    int i;
    
    if (!line)
        return (NULL);
    i = 0;
    while (ft_strchr(" \t\v\f\r", line[i]) && line[i])
        i++;
    addback(tokens, " ", SPACE);
    return (line + i);
}

char    *is_dollar_pipe(t_token_list **tokens, char *line)
{
    if (!line)
        return (NULL);
    if(*line == '$')
    {
		if (*(line + 1) == '$')
		{
			addback(tokens, "$$", WORD);
        	return (line + 2);
		}
        addback(tokens,"$", DOLLAR);
        line = afdollar(tokens, line + 1);
        return (line);
    }
    else if(*line == '|')
    {
        addback(tokens,"|", PIPE);
        return (line + 1);
    }
	return (0);
}

char    *is_word(t_token_list **tokens, char *line)
{
    int		i;

    if (!line)
        return (NULL);
    char    *word;

    i = 0;
    while (!ft_strchr(" \t\v\f\r><|$\'\"", line[i]))
        i++;
	word = malloc(i + 1);
	i = 0;
	while (!ft_strchr(" \t\v\f\r><|$\'\"", line[i]))
	{
		
		word[i] = line[i];
		i++;
	}
	word[i] = '\0';
	addback(tokens, word, WORD);
	return (line + i);
}

char	*afdollar(t_token_list **tokens, char *line)
{
	int	i;
	int j;
	char *afdollar;

    if (!line)
        return (NULL);
	i = 0;
	j = 0;
	while (line[i])
	{
		if ((line[i] != 34) && (ft_isalnum(line[i]) || line[i] == '_'))
			i++;
		else
			break;
	}
	afdollar = malloc(i + 1);
	while (j < i)
	{
		afdollar[j] = line[j];
		j++;
	}
	afdollar[j] = '\0';
	addback(tokens, afdollar, AFDOLLAR);
	return (line + i);
}